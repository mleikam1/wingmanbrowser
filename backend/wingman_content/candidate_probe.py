"""Resumable, operator-only technical probes over the imported fixed inventory.

This module counts supplied metadata, not publication/display permission. It uses
the production public-DNS-pinned fetcher unchanged and never fetches article/media URLs.
"""
import hashlib
import re
import time
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, urlunsplit
from defusedxml import ElementTree
from .candidates import atomic_json, permitted_url, reviews_for
from .fetch import FetchError, PinnedHTTPSConnection, SecureFeedFetcher, MAX_XML_BYTES
from .normalize import date_value, iso, plain
from .provider import delay_seconds

ATOM = "{http://www.w3.org/2005/Atom}"
RSS1 = "{http://purl.org/rss/1.0/}"
MEDIA = "{http://search.yahoo.com/mrss/}"
CONTENT = "{http://purl.org/rss/1.0/modules/content/}"
MIN_INTERVAL = 1800
MAX_BATCH = 24
MAX_WORKERS = 3


def metadata_url(value):
    try:
        parsed = urlsplit(value.strip())
        if (len(value) > 4096 or parsed.scheme not in ("https", "http") or not parsed.hostname
                or parsed.username is not None or parsed.password is not None or "\\" in value
                or any(ord(c) < 33 or ord(c) == 127 for c in value)):
            return None
        return urlunsplit((parsed.scheme, parsed.netloc, parsed.path or "/", parsed.query, ""))
    except (ValueError, AttributeError):
        return None


class ImageCandidates(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.urls = set()

    def handle_starttag(self, tag, attrs):
        if tag.lower() != "img":
            return
        attrs = dict(attrs)
        if attrs.get("width") in ("0", "1") or attrs.get("height") in ("0", "1"):
            return
        url = metadata_url(attrs.get("src", ""))
        if url:
            self.urls.add(url)


def inspect_feed(body, now):
    """Return bounded counts/dates only. Do not persist unlicensed article text."""
    if len(body) > MAX_XML_BYTES:
        raise ValueError("xml-size-limit")
    root = ElementTree.fromstring(body, forbid_dtd=True, forbid_entities=True, forbid_external=True)
    nodes = 0
    stack = [(root, 0)]
    while stack:
        node, depth = stack.pop()
        nodes += 1
        if nodes > 20000 or depth > 32:
            raise ValueError("xml-structure-limit")
        stack.extend((child, depth + 1) for child in node)
    branding = []
    if root.tag == "rss" and root.find("channel") is not None:
        channel = root.find("channel")
        entries, kind = channel.findall("item"), "rss-2"
        candidate = metadata_url(channel.findtext("image/url", ""))
        if candidate:
            branding.append(candidate)
    elif root.tag == ATOM + "feed":
        entries, kind = root.findall(ATOM + "entry"), "atom-1"
        branding = [value for name in ("logo", "icon")
                    if (value := metadata_url(root.findtext(ATOM + name, "")))]
    elif root.tag == "{http://www.w3.org/1999/02/22-rdf-syntax-ns#}RDF":
        entries, kind = root.findall(RSS1 + "item"), "rss-1"
    elif root.tag.lower().endswith("html"):
        raise ValueError("html-response")
    else:
        raise ValueError("unrecognized-feed-format")
    if len(entries) > 500:
        raise ValueError("entry-count-limit")
    counts = {"items": len(entries), "itemsWithTitles": 0, "itemsWithLinks": 0,
              "itemsWithExcerpts": 0, "itemsWithImageCandidates": 0,
              "itemsWithPublishedDates": 0, "itemsWithUpdatedDates": 0,
              "missingPublishedDates": 0, "invalidPublishedDates": 0,
              "futurePublishedDates": 0, "duplicateArticleUrls": 0,
              "brandingCandidates": len(set(branding))}
    dates, urls, examples = [], set(), []
    for entry in entries:
        atom = kind == "atom-1"
        ns = ATOM if atom else RSS1 if kind == "rss-1" else ""
        title = "".join(entry.find(ns + "title").itertext()) if entry.find(ns + "title") is not None else ""
        excerpt_node = entry.find(ns + ("summary" if atom else "description"))
        excerpt = "".join(excerpt_node.itertext()) if excerpt_node is not None else ""
        if len(title) > 100000 or len(excerpt) > 100000:
            raise ValueError("metadata-size-limit")
        counts["itemsWithTitles"] += bool(plain(title, 100000))
        counts["itemsWithExcerpts"] += bool(plain(excerpt, 100000))
        url = None
        if atom:
            for link in entry.findall(ATOM + "link"):
                if link.get("rel", "alternate") == "alternate":
                    url = metadata_url(link.get("href", ""))
                    if url:
                        break
        else:
            url = metadata_url(entry.findtext(ns + "link", ""))
        if url:
            counts["itemsWithLinks"] += 1
            counts["duplicateArticleUrls"] += url in urls
            urls.add(url)
        published_raw = entry.findtext(ns + ("published" if atom else "pubDate"))
        if not published_raw and not atom:
            published_raw = entry.findtext("{http://purl.org/dc/elements/1.1/}date")
        published = date_value(published_raw)
        if not published_raw:
            counts["missingPublishedDates"] += 1
        elif published is None:
            counts["invalidPublishedDates"] += 1
        elif published > now + timedelta(hours=24):
            counts["futurePublishedDates"] += 1
        else:
            dates.append(published)
            counts["itemsWithPublishedDates"] += 1
        counts["itemsWithUpdatedDates"] += bool(atom and date_value(entry.findtext(ATOM + "updated")))
        images = set()
        for node in entry.iter():
            if node.tag in (MEDIA + "thumbnail", MEDIA + "content"):
                if node.get("width") in ("0", "1") or node.get("height") in ("0", "1"):
                    continue
                if node.tag == MEDIA + "content" and node.get("medium", "image") != "image" and not node.get("type", "").startswith("image/"):
                    continue
                image = metadata_url(node.get("url", ""))
            elif node.tag == "enclosure" or (node.tag == ATOM + "link" and node.get("rel") == "enclosure"):
                image = metadata_url(node.get("url", node.get("href", ""))) if node.get("type", "").startswith("image/") else None
            else:
                continue
            if image:
                images.add(image)
        detector = ImageCandidates()
        detector.feed(excerpt)
        # Supplied full HTML is inspected for availability only, not permission
        # to display its text or images. No script or network resource executes.
        content = entry.findtext(CONTENT + "encoded", "") or entry.findtext(ATOM + "content", "")
        if len(content) > 100000:
            raise ValueError("metadata-size-limit")
        detector.feed(content)
        images.update(detector.urls)
        counts["itemsWithImageCandidates"] += bool(images)
        if len(examples) < 5:
            examples.append({"articleUrl": url, "articleId": hashlib.sha256(url.encode()).hexdigest()[:32] if url else None,
                             "publishedAt": iso(published) if published and published <= now + timedelta(hours=24) else None,
                             "imageCandidateCount": len(images), "excerptCharacters": len(plain(excerpt, 100000))})
    counts.update(newestPublishedAt=iso(max(dates)) if dates else None,
                  oldestPublishedAt=iso(min(dates)) if dates else None,
                  uniqueArticleUrls=len(urls), metadataExamples=examples)
    return kind, counts


class ObservedConnection:
    """Read-only diagnostics around the existing pinned TLS connection."""
    def __init__(self, connection, host, trace):
        self.connection, self.host, self.trace = connection, host, trace
        self.url = None

    @property
    def sock(self):
        return self.connection.sock

    def request(self, method, path, **kwargs):
        self.url = "https://" + self.host + path
        return self.connection.request(method, path, **kwargs)

    def getresponse(self):
        response = self.connection.getresponse()
        headers = {k.lower(): v for k, v in response.getheaders()}
        self.trace.append({"url": self.url, "status": response.status,
                           "contentType": headers.get("content-type"),
                           "location": headers.get("location")})
        return response

    def close(self):
        self.connection.close()


def observed_fetch(source, validators):
    trace = []
    def connector(host, address, timeout):
        return ObservedConnection(PinnedHTTPSConnection(host, address, timeout), host, trace)
    try:
        return SecureFeedFetcher(connector=connector).fetch(source, validators), trace, None
    except FetchError as error:
        return None, trace, error


def probe_configuration(endpoint, inventory, reviews):
    url = endpoint["originalUrl"]
    hosts = [urlsplit(url).hostname] if permitted_url(url) else []
    history = []
    for record in inventory["records"]:
        if record["endpointId"] != endpoint["id"]:
            continue
        for review in reviews_for(record, reviews):
            correction = review.get("endpointCorrection")
            if correction:
                if (correction.get("originalUrl") != endpoint["originalUrl"]
                        or not permitted_url(correction.get("resolvedUrl", ""))
                        or not correction.get("evidenceUrls") or not correction.get("reviewedAt")):
                    raise ValueError("Endpoint correction lacks exact original URL and publisher evidence")
                url = correction["resolvedUrl"]
                hosts = [urlsplit(url).hostname]
                history.append(correction)
            configured = review.get("sourceConfig", {})
            if configured.get("feedUrl") == url:
                approved_hosts = configured.get("feedRedirectHosts", [])
                if all(isinstance(h, str) and re.fullmatch(r"[a-z0-9.-]+", h) for h in approved_hosts):
                    hosts = sorted(set(hosts + approved_hosts))
    return {"id": endpoint["id"], "feedUrl": url, "feedRedirectHosts": hosts}, history


def probe(endpoint, inventory, reviews, prior, fetch=observed_fetch, clock=None):
    clock = clock or (lambda: datetime.now(timezone.utc))
    started = clock()
    source, history = probe_configuration(endpoint, inventory, reviews)
    compatible = prior.get("requestUrl") == source["feedUrl"] and prior.get("probeVersion") == 1
    validators = {}
    if compatible and prior.get("coverage"):
        for field, header in (("etag", "If-None-Match"), ("lastModified", "If-Modified-Since")):
            if prior.get(field):
                validators[header] = prior[field]
    result = {"probeVersion": 1, "endpointId": endpoint["id"], "originalUrl": endpoint["originalUrl"],
              "requestUrl": source["feedUrl"], "attemptedAt": iso(started), "endpointHistory": history,
              "resolvedUrl": None, "httpStatus": None, "format": None, "coverage": None,
              "status": "review-needed", "reason": None, "failures": prior.get("failures", 0),
              "networkAttempted": permitted_url(source["feedUrl"])}
    if not permitted_url(source["feedUrl"]):
        response, trace, error = None, [], FetchError("https-endpoint-evidence-required")
    else:
        response, trace, error = fetch(source, validators)
    now = clock()
    result["checkedAt"] = iso(now)
    result["trace"] = trace[:4]
    if trace:
        result["resolvedUrl"] = trace[-1]["url"]
        result["httpStatus"] = trace[-1]["status"]
        if trace[-1].get("location"):
            result["unfollowedRedirectTarget"] = urljoin(trace[-1]["url"], trace[-1]["location"])
    headers = response.headers if response else {}
    if error:
        reason = error.reason
        result["reason"] = reason
        if reason == "http-429":
            result["status"] = "rate-limited"
        elif reason in ("http-401", "http-403", "http-451"):
            result["status"] = "access-restricted"
        elif reason == "unexpected-content-type" and trace and "html" in (trace[-1].get("contentType") or "").lower():
            result["status"] = "html-login-challenge-response"
        elif reason in ("https-endpoint-evidence-required", "unconfigured-feed-destination", "invalid-feed-url", "non-public-dns", "unexpected-content-type"):
            result["status"] = "review-needed"
        else:
            result["status"] = "unreachable"
        if error.retry_after:
            headers = {"retry-after": error.retry_after}
    else:
        result.update(httpStatus=response.status, resolvedUrl=result["resolvedUrl"] or source["feedUrl"],
                      bytes=len(response.body), rawSha256=hashlib.sha256(response.body).hexdigest() if response.body else prior.get('rawSha256'),
                      etag=headers.get("etag"), lastModified=headers.get("last-modified"))
        try:
            if response.status == 304:
                if not compatible or not prior.get("coverage"):
                    raise ValueError("unconditional-304")
                kind, coverage = prior["format"], prior["coverage"]
                result["etag"] = result["etag"] or prior.get("etag")
                result["lastModified"] = result["lastModified"] or prior.get("lastModified")
            else:
                kind, coverage = inspect_feed(response.body, now)
            result.update(format=kind, coverage=coverage, failures=0)
            latest = date_value(coverage.get("newestPublishedAt"))
            if not coverage["items"] or not coverage["itemsWithTitles"] or not coverage["itemsWithLinks"]:
                result.update(status="review-needed", reason="empty-or-missing-title-link-metadata")
            elif latest and latest < now - timedelta(days=30):
                result.update(status="stale", reason="newest-publisher-date-older-than-30-days")
            else:
                redirected = len(trace) > 1 or (response.status == 304 and prior.get("status") == "redirected")
                result.update(status="redirected" if redirected else "working", reason=None)
        except Exception as exc:
            reason = str(exc)[:200]
            result.update(status="html-login-challenge-response" if reason == "html-response" else "malformed",
                          reason=reason or "invalid-feed")
    failed = result["status"] not in ("working", "redirected", "stale")
    if failed:
        result["failures"] = min(12, int(prior.get("failures", 0)) + 1)
    floor = min(86400, MIN_INTERVAL * 2 ** max(0, result["failures"] - 1)) if failed else MIN_INTERVAL
    delay = delay_seconds(headers, now, floor)
    result["nextCheckAt"] = iso(now + timedelta(seconds=delay)) if delay is not None else None
    result["suspended"] = delay is None
    return result


def run_validation(inventory, state, state_path, reviews=None, batch_size=24, concurrency=3,
                   probe_function=probe, clock=None, run_seconds=240, priority_records=()):
    if not 1 <= batch_size <= MAX_BATCH or not 1 <= concurrency <= MAX_WORKERS or not 1 <= run_seconds <= 300:
        raise ValueError("Probe batch/concurrency/deadline exceeds bounded operator limits")
    clock = clock or (lambda: datetime.now(timezone.utc))
    state = state or {"schemaVersion": 1, "endpoints": {}, "cursor": 0}
    if state.get("schemaVersion") != 1 or not isinstance(state.get("endpoints"), dict):
        raise ValueError("Invalid validation checkpoint; refusing to reset pacing")
    endpoints = list(inventory["endpoints"])
    prioritized = {r["endpointId"] for r in inventory["records"] if r["recordId"] in priority_records}
    endpoints.sort(key=lambda e: e["id"] not in prioritized)
    size = len(endpoints)
    cursor = state.get("cursor", 0)
    if type(cursor) is not int or cursor < 0:
        raise ValueError("Invalid validation cursor")
    now = clock()
    queue = []
    for step in range(size):
        index = (cursor + step) % size
        endpoint = endpoints[index]
        previous = state["endpoints"].get(endpoint["id"], {})
        due = date_value(previous.get("nextCheckAt"))
        if previous.get("nextCheckAt") is not None and due is None:
            raise ValueError("Invalid checkpoint pacing timestamp")
        if not previous.get("suspended") and (due is None or due <= now):
            queue.append((index, endpoint, previous))
        if len(queue) >= batch_size:
            break
    state["inputSha256"] = inventory["inputSha256"]
    deadline = time.monotonic() + run_seconds
    completed, active, busy_hosts = [], {}, set()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        while queue or active:
            while len(active) < concurrency and queue and time.monotonic() < deadline:
                selected = next((i for i, (_, e, _) in enumerate(queue)
                                 if urlsplit(e["originalUrl"]).hostname not in busy_hosts), None)
                if selected is None:
                    break
                index, endpoint, prior = queue.pop(selected)
                host = urlsplit(endpoint["originalUrl"]).hostname
                # Durable pre-attempt hold: process death cannot immediately
                # restart the same endpoint or erase an observed publisher hold.
                attempted = clock()
                state["cursor"] = (index + 1) % size
                state["endpoints"][endpoint["id"]] = dict(prior, attemptedAt=iso(attempted),
                    nextCheckAt=iso(attempted + timedelta(seconds=MIN_INTERVAL)),
                    inFlight=True, status=prior.get("status", "not-yet-checked"))
                atomic_json(state_path, state)
                future = pool.submit(probe_function, endpoint, inventory, reviews or {}, prior, clock=clock)
                active[future] = (endpoint, host)
                busy_hosts.add(host)
            if not active:
                break
            finished, _ = wait(active, return_when=FIRST_COMPLETED)
            for future in finished:
                endpoint, host = active.pop(future)
                busy_hosts.discard(host)
                try:
                    result = future.result()
                except Exception as error:
                    stamp = clock()
                    result = dict(state["endpoints"][endpoint["id"]], checkedAt=iso(stamp),
                                  status="review-needed", reason="probe-error:" + type(error).__name__)
                result["inFlight"] = False
                state["endpoints"][endpoint["id"]] = result
                state["updatedAt"] = iso(clock())
                atomic_json(state_path, state)
                completed.append(endpoint["id"])
    return state, {"attemptedEndpoints": len(completed), "endpointIds": completed,
                   "cursor": state["cursor"], "generatedAt": iso(clock()),
                   "remainingUnattempted": sum(not state["endpoints"].get(e["id"], {}).get("checkedAt") for e in endpoints)}
