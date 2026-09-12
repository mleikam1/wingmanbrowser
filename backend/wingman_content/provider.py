"""Provider-neutral ingestion and common snapshot publication."""
import hashlib
import re
from abc import ABC, abstractmethod
from datetime import datetime, timedelta, timezone
from .config import registry
from .fetch import FetchError, SecureFeedFetcher
from .normalize import date_value, iso, parse_feed, canonical_url, item_id
from .store import encode

MAX_SHARED_ITEMS = 300
MAX_SNAPSHOT_BYTES = 512 * 1024
MAX_FAILURES = 12
NORMALIZATION_VERSION = 4
MAX_REVOCATIONS = 5000  # Matches the client envelope limit.


class NewsProvider(ABC):
    @abstractmethod
    def refresh(self, source, prior, now):
        """Return validated normalized source state; never accepts user context."""


def delay_seconds(headers, now, floor):
    cache = headers.get("cache-control", "")
    maxima = re.findall(r"(?:^|,)\s*(?:max-age|s-maxage)\s*=\s*\"?(\d+)", cache, re.I)
    if any(len(value) > 10 for value in maxima):
        return None
    delay = max([floor] + [int(value) for value in maxima])
    retry = headers.get("retry-after")
    if retry:
        if retry.isdigit():
            if len(retry) > 10:
                return None
            delay = max(delay, int(retry))
        else:
            parsed = date_value(retry)
            if parsed:
                delay = max(delay, max(0, int((parsed - now).total_seconds())))
    # An extreme publisher hold pauses the source for operator review; it must
    # never be shortened into an earlier request by an internal delay cap.
    return delay if delay <= 366 * 86400 else None


class RssAtomProvider(NewsProvider):
    def __init__(self, destination_policy, fetcher=None):
        self.destination_policy = destination_policy
        self.fetcher = fetcher or SecureFeedFetcher()

    def refresh(self, source, prior, now):
        normalization_key = hashlib.sha256(encode({"version": NORMALIZATION_VERSION,
                                                  "source": source})).hexdigest()
        validators = {}
        compatible = prior.get("normalizationKey") == normalization_key
        if compatible and prior.get("etag"):
            validators["If-None-Match"] = prior["etag"]
        if compatible and prior.get("lastModified"):
            validators["If-Modified-Since"] = prior["lastModified"]
        response = self.fetcher.fetch(source, validators)
        cache_control = response.headers.get("cache-control", prior.get("cacheControl", "") if response.status == 304 else "")
        if re.search(r"(?:^|,)\s*(?:no-store|private)(?:\s*(?:,|=|$))", cache_control, re.I):
            raise FetchError("source-cache-prohibited")
        if response.status == 304:
            if not prior.get("lastSuccessAt") or not compatible:
                raise FetchError("unconditional-304")
            items, held, deleted = prior.get("items", []), {"count": prior.get("heldCount", 0),
                "reasons": prior.get("heldReasons", {}), "examples": prior.get("heldExamples", [])}, []
            # Successful revalidation updates freshness, never publication date.
            items = [dict(item, fetchedAt=iso(now),
                          expiresAt=iso(now + timedelta(seconds=source["retentionSeconds"]))) for item in items]
        else:
            items, held, deleted = parse_feed(response.body, source, now, self.destination_policy)
        # A rolling feed's ordinary omission is not called publisher revocation.
        # Omitted items leave this finite snapshot; explicit tombstones persist.
        revoked = set(prior.get("revokedItemIds", []))
        deleted_hashes = {hashlib.sha256(ref.encode()).hexdigest() for ref in deleted}
        for old in prior.get("items", []):
            if (old.get("_guidHash") in deleted_hashes or old.get("_guid") in deleted
                    or old["canonicalUrl"] in deleted):
                revoked.add(old["id"])
        for ref in deleted:
            url = canonical_url(ref, source)
            if url:
                revoked.add(item_id(url))
        delay = delay_seconds(dict(response.headers, **{"cache-control": cache_control}), now, source["minRefreshSeconds"])
        return {"items": items, "normalizationVersion": NORMALIZATION_VERSION, "normalizationKey": normalization_key,
                "cacheControl": cache_control,
                "etag": response.headers.get("etag", prior.get("etag") if response.status == 304 else None),
                "lastModified": response.headers.get("last-modified", prior.get("lastModified") if response.status == 304 else None),
                "lastSuccessAt": iso(now), "fetchedAt": iso(now),
                "nextRefreshAt": iso(now + timedelta(seconds=delay)) if delay is not None else None,
                "refreshSuspended": delay is None,
                "failures": 0, "error": None, "heldCount": held["count"],
                "heldReasons": held["reasons"], "heldExamples": held["examples"], "lastHttpStatus": response.status,
                "revokedItemIds": sorted(revoked), "status": "fresh"}


def is_unexpired(item, now):
    expires = date_value(item.get("expiresAt"))
    return expires is not None and expires > now


def item_current(item, now):
    published = date_value(item.get("publishedAt"))
    return published is None or published >= now - timedelta(days=30)


def public_snapshot(config, states, now, prior_snapshot=None):
    sources, by_url, revoked_sources, stale = [], {}, [], []
    revoked = set((prior_snapshot or {}).get("revokedItemIds", []))
    # Removed config entries are explicit source revocations, including offline.
    current_ids = {s["id"] for s in config["sources"]}
    for old in (prior_snapshot or {}).get("sources", []):
        if old["id"] not in current_ids:
            revoked_sources.append(old["id"])
    for source in config["sources"]:
        state = states.get(source["id"], {})
        revoked.update(source.get("revokedItemIds", []))
        revoked.update(state.get("revokedItemIds", []))
        for url in source.get("revokedUrls", []):
            canonical = canonical_url(url, source)
            if canonical:
                revoked.add(item_id(canonical))
        status = state.get("status", "unavailable")
        if not source["enabled"] or state.get("sourceRevoked"):
            status = "revoked"
            revoked_sources.append(source["id"])
        elif not state.get("lastSuccessAt"):
            status = "unavailable"
        elif state.get("error") or (date_value(state.get("nextRefreshAt")) or now) <= now:
            status = "cached"
        if status in ("cached", "unavailable"):
            stale.append(source["id"])
        metadata = {key: source[key] for key in ("id", "name", "homepageUrl", "language", "topics", "rights")}
        metadata.update(status=status, fetchedAt=state.get("fetchedAt"),
                        lastSuccessAt=state.get("lastSuccessAt"), nextRefreshAt=state.get("nextRefreshAt"))
        sources.append(metadata)
        if status in ("revoked", "unavailable"):
            continue
        for item in state.get("items", []):
            if item["id"] in revoked or not is_unexpired(item, now) or not item_current(item, now):
                continue
            # Config changes cannot be bypassed by cached normalization.
            if not canonical_url(item["canonicalUrl"], source):
                continue
            candidate = {key: value for key, value in item.items() if not key.startswith("_")}
            candidate["rights"] = {"title": True, "excerpt": source["rights"]["excerpts"],
                                   "image": False, "licenseUrl": source["rights"]["licenseUrl"]}
            if not source["rights"]["excerpts"]:
                candidate.pop("excerpt", None)
            # Stable URL identity wins deterministically; distinct articles with
            # the same headline are never collapsed.
            by_url.setdefault(candidate["canonicalUrl"], candidate)
    revoked_sources = sorted(set(revoked_sources) | set((prior_snapshot or {}).get("revokedSourceIds", [])))
    items = [item for item in by_url.values() if item["id"] not in revoked
             and item["sourceId"] not in revoked_sources]
    items.sort(key=lambda item: (item.get("publishedAt") or "", item["id"]), reverse=True)
    items = items[:MAX_SHARED_ITEMS]
    result = {"schemaVersion": 1, "snapshotId": "0" * 32, "generatedAt": iso(now),
              "expiresAt": iso(now + timedelta(seconds=1800)), "sources": sources, "items": items,
              "revokedItemIds": sorted(revoked), "revokedSourceIds": revoked_sources,
              "staleSourceIds": stale}
    if len(revoked) > MAX_REVOCATIONS:
        # Preserve the effect of every item revocation with a source-wide halt,
        # rather than emit an envelope the client cannot parse or drop old IDs.
        result.update(items=[], revokedItemIds=[], recoveryRequired=True,
                      revokedSourceIds=sorted(set(revoked_sources) | current_ids))
        for source in result['sources']:
            source['status'] = 'revoked'
    while len(encode(result)) > MAX_SNAPSHOT_BYTES and result["items"]:
        result["items"].pop()
    if len(encode(result)) > MAX_SNAPSHOT_BYTES:
        raise ValueError("Snapshot metadata/revocation size limit")
    result["snapshotId"] = hashlib.sha256(encode(result)).hexdigest()[:32]
    return result


def ingest(config, store, provider, now=None):
    live_clock = now is None
    now = now or datetime.now(timezone.utc)
    prior = store.read() or {"states": {}, "snapshot": {}}
    states, report = {}, []
    for source in config["sources"]:
        source_now = datetime.now(timezone.utc) if live_clock else now
        previous = prior.get("states", {}).get(source["id"], {})
        state = dict(previous)
        due = date_value(state.get("nextRefreshAt"))
        action = ("disabled" if not source["enabled"] else "source-revoked" if state.get("sourceRevoked")
                  else "suspended" if state.get("refreshSuspended") else "not-due")
        if source["enabled"] and not state.get("sourceRevoked") and not state.get("refreshSuspended") and (due is None or source_now >= due):
            try:
                state = provider.refresh(source, previous, source_now)
                action = "http-%d" % state["lastHttpStatus"]
            except Exception as exc:
                # One bounded attempt per due run; retry next scheduled run with
                # exponential backoff. No multiplicative immediate retry storm.
                failures = min(MAX_FAILURES, previous.get("failures", 0) + 1)
                delay = min(21600, source["minRefreshSeconds"] * 2 ** (failures - 1))
                if isinstance(exc, FetchError) and exc.retry_after:
                    delay = delay_seconds({"retry-after": exc.retry_after}, source_now, delay)
                reason = exc.reason if isinstance(exc, FetchError) else "invalid-feed"
                state.update(failures=failures, nextRefreshAt=iso(source_now + timedelta(seconds=delay)) if delay is not None else None,
                             refreshSuspended=delay is None,
                             error=reason, status="cached" if previous.get("lastSuccessAt") else "unavailable")
                if reason == "source-cache-prohibited":
                    # A newly prohibited shared cache cannot keep serving old text.
                    state["revokedItemIds"] = sorted(set(state.get("revokedItemIds", [])) |
                                                     {item["id"] for item in state.get("items", [])})
                    state["items"] = []
                action = reason
        # Do not retain bodies, HTML, image URLs or expired normalized records.
        state["items"] = [item for item in state.get("items", []) if is_unexpired(item, source_now)]
        states[source["id"]] = state
        report.append({"sourceId": source["id"], "action": action, "items": len(state.get("items", [])),
                       "held": state.get("heldCount", 0), "heldReasons": state.get("heldReasons", {}),
                       "heldExamples": state.get("heldExamples", []), "nextRefreshAt": state.get("nextRefreshAt")})
    snapshot = public_snapshot(config, states, datetime.now(timezone.utc) if live_clock else now, prior.get("snapshot"))
    if snapshot.get('recoveryRequired'):
        for state in states.values():
            state.update(sourceRevoked=True, items=[], revokedItemIds=[])
    store.write({"schemaVersion": 1, "states": states, "snapshot": snapshot})
    return snapshot, report
