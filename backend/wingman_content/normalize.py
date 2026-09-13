"""RSS/Atom normalization and conservative source-scoped eligibility."""
import hashlib
import html
import json
import re
import unicodedata
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit
from defusedxml import ElementTree

BASELINE_SHA256 = "f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f"
CATEGORIES = {"sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion",
              "tobacco-nicotine", "security-threat"}
ATOM = "{http://www.w3.org/2005/Atom}"
TOMBSTONE = "{http://purl.org/atompub/tombstones/1.0}"
MAX_ENTRIES = 500
MAX_TITLE = 200
MAX_EXCERPT = 400


def iso(value):
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def date_value(value, now=None):
    if not isinstance(value, str) or len(value) > 100:
        return None
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        try:
            parsed = parsedate_to_datetime(value.strip())
        except (ValueError, TypeError, OverflowError):
            return None
    if not parsed or parsed.tzinfo is None:
        return None
    parsed = parsed.astimezone(timezone.utc)
    if parsed.year < 1990 or (now and parsed > now + timedelta(hours=24)):
        return None
    return parsed


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript", "iframe", "svg"):
            self.hidden += 1
        if tag in ("p", "br", "div", "li") and not self.hidden:
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript", "iframe", "svg") and self.hidden:
            self.hidden -= 1
        if tag in ("p", "div", "li") and not self.hidden:
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def plain(value, limit):
    parser = PlainText()
    parser.feed(value[:100000])
    text = unicodedata.normalize("NFKC", html.unescape(" ".join(parser.parts)))
    text = " ".join("".join(c for c in text if c in "\t\n\r" or
                            unicodedata.category(c) not in ("Cc", "Cf")).split())
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0] + "…"
    return text


def canonical_url(value, source):
    value = html.unescape(value.strip())
    if len(value) > 4096 or "\\" in value or any(ord(c) < 33 or ord(c) == 127 for c in value):
        return None
    try:
        parsed = urlsplit(value)
        if (parsed.scheme != "https" or parsed.hostname not in source["allowedArticleHosts"]
                or parsed.username is not None or parsed.password is not None
                or parsed.port not in (None, 443)):
            return None
        path = unquote(parsed.path or "/")
        if ("\\" in path or any(c in path for c in ("\x00", "\r", "\n"))
                or any(part in (".", "..") for part in path.split("/"))):
            return None
        if source.get('articleUrlFormat') == 'dated-story' and not re.fullmatch(
                r'/[0-9]{4}/[0-9]{2}/[0-9]{2}/[^/]+/?', path):
            return None
        if not any(path.startswith(prefix) for prefix in source["articlePathPrefixes"]):
            return None
        query = [(key, value) for key, value in parse_qsl(parsed.query, keep_blank_values=True,
                                                        max_num_fields=40)
                 if not key.lower().startswith("utm_") and key.lower() not in
                 ("fbclid", "gclid", "mc_cid", "mc_eid")]
        return urlunsplit(("https", parsed.hostname, parsed.path or "/", urlencode(query), ""))
    except (ValueError, UnicodeError):
        return None


def item_id(url):
    return hashlib.sha256(url.encode()).hexdigest()[:32]


def matches_topic_scope(title, excerpt, source):
    terms = source.get('requiredTopicTerms', [])
    text = title + ' ' + excerpt
    return not terms or any(re.search(r'\b' + re.escape(term) + r'\b', text, re.I)
                            for term in terms)


def item_topics(url, source):
    if source['id'] == 'nasa-technology':
        parsed = urlsplit(url)
        return ['science', 'technology'] if parsed.hostname == 'www.nasa.gov' and parsed.path.startswith('/technology/') else ['science']
    return source['topics']


class DestinationPolicy:
    def __init__(self, path):
        data = Path(path).read_bytes()
        if hashlib.sha256(data).hexdigest() != BASELINE_SHA256:
            raise ValueError("Consumer protection baseline integrity failure")
        raw = json.loads(data)
        if set(raw["categories"]) != CATEGORIES or any(not raw["categories"][c] for c in CATEGORIES):
            raise ValueError("Incomplete consumer protection baseline")
        self.domains = frozenset(domain for domains in raw["categories"].values() for domain in domains)
        self.path_rules = raw["pathRules"]

    def allows(self, url):
        parsed = urlsplit(url)
        host = (parsed.hostname or "").lower().rstrip(".")
        labels = host.split(".")
        if any(".".join(labels[index:]) in self.domains for index in range(len(labels))):
            return False
        path = unquote(parsed.path).lower()
        for rule in self.path_rules:
            prefix = rule["pathPrefix"].lower().rstrip("/")
            if (host == rule["host"] or host.endswith("." + rule["host"])) and (
                    path == prefix or path.startswith(prefix + "/")):
                return False
        return True


# These checks can hold an item, never positively certify arbitrary text as safe.
# Source review, rights, publication type, exact host/path and destination policy
# are separate mandatory evidence. No arbitrary article text is sent to an AI service.
PROMOTION = re.compile(r"\b(sponsored(?:\s+content)?|paid\s+(?:post|partnership|advertisement)|"
                       r"affiliate\s+links?|buy\s+now|shop\s+now|promo\s+code|"
                       r"casino\s+bonus|place\s+(?:a\s+)?bets?|free\s+spins|"
                       r"adult\s+entertainment|pornograph\w*|vape\s+(?:shop|sale)|"
                       r"cannabis\s+dispensary|all\s+rights\s+reserved|"
                       r"copyright\s+(?!nasa\b|noaa\b|usgs\b)[a-z])", re.I)
AMBIGUOUS_RESTRICTED = re.compile(r"\b(casino|sportsbook|vaping|pornography|cannabis|marijuana|"
                                 r"tobacco|cigarettes|vodka|whiskey|beer|wine)\b", re.I)
REPORTING_CONTEXT = re.compile(r"\b(research|study|scientists?|health|pollution|wildlife|"
                              r"survey|geology|water|environment|hazard|report|evidence)\b", re.I)


def text_eligible(title, excerpt, categories):
    text = " ".join((title, excerpt, " ".join(categories)))
    if PROMOTION.search(text) or "©" in text or re.search(r"\bcopyright\s+\d{4}\b", text, re.I):
        return False
    if AMBIGUOUS_RESTRICTED.search(text) and not REPORTING_CONTEXT.search(text):
        return False
    return bool(title)


def parse_feed(data, source, now, destination_policy):
    if len(data) > 2 * 1024 * 1024:
        raise ValueError("XML size limit")
    root = ElementTree.fromstring(data, forbid_dtd=True, forbid_entities=True, forbid_external=True)
    if root.tag == "rss":
        entries = root.findall("./channel/item")
        atom = False
    elif root.tag == ATOM + "feed":
        entries = root.findall(ATOM + "entry")
        atom = True
    else:
        raise ValueError("Not an RSS 2 or Atom feed")
    if len(entries) > MAX_ENTRIES or sum(1 for _ in root.iter()) > 20000:
        raise ValueError("XML entry/node limit")
    items, held, deleted = [], {"count": 0, "reasons": {}, "examples": []}, []
    for tombstone in root.findall(TOMBSTONE + "deleted-entry"):
        if tombstone.get("ref"):
            deleted.append(tombstone.get("ref")[:4096])
    for entry in entries:
        prefix = ATOM if atom else ""
        title_raw = entry.findtext(prefix + "title") or ""
        excerpt_raw = entry.findtext(prefix + ("summary" if atom else "description")) or ""
        title = plain(title_raw, MAX_TITLE)
        excerpt = plain(excerpt_raw, MAX_EXCERPT)
        links = [node.get("href") for node in entry.findall(ATOM + "link")
                 if node.get("rel", "alternate") == "alternate"] if atom else [entry.findtext("link")]
        url = next((canonical for link in links if link
                    for canonical in [canonical_url(link, source)] if canonical), None)
        categories = [(node.get("term") or node.text or "") for node in entry.findall(prefix + "category")]
        # Inspect full bounded descriptions before truncation so a late rights/promo
        # notice cannot disappear at the displayed excerpt boundary.
        review_text = plain(excerpt_raw, 100000)
        full_title = plain(title_raw, 100000)
        attribution_raw = (entry.findtext(ATOM + "author/" + ATOM + "name") if atom else
                           entry.findtext("{http://purl.org/dc/elements/1.1/}creator") or entry.findtext("author")) or ""
        rights_raw = entry.findtext(ATOM + "rights" if atom else "{http://purl.org/dc/elements/1.1/}rights") or ""
        guid = entry.findtext(prefix + ("id" if atom else "guid")) or url
        reason = ("metadata-size-limit" if any(len(value) > 100000 for value in
                                              (title_raw, excerpt_raw, attribution_raw, rights_raw))
                  else "unreviewed-destination" if not url else "destination-policy" if not destination_policy.allows(url)
                  else "missing-author" if source.get('requiresAttribution') and not plain(attribution_raw, 200)
                  else "promotion-or-rights-ambiguity" if not text_eligible(full_title, review_text + " " + plain(rights_raw, 100000), categories)
                  else "outside-topic-scope" if not matches_topic_scope(full_title, review_text, source)
                  else None)
        if reason:
            held["count"] += 1
            held["reasons"][reason] = held["reasons"].get(reason, 0) + 1
            if len(held["examples"]) < 10:
                held["examples"].append({"title": title, "reason": reason,
                                         "url": (links[0] or "")[:4096] if links else ""})
            # A topic mismatch is local to this feed. It must not withdraw the
            # same article from a different approved section (e.g. Sports).
            # Rights/safety failures still revoke previously cached records.
            if reason != "outside-topic-scope":
                if guid:
                    deleted.append(guid[:4096])
                if url:
                    deleted.append(url)
            continue
        published = date_value(entry.findtext(prefix + ("published" if atom else "pubDate")), now)
        # Atom updated is an edit timestamp, not proof of first publication.
        item = {"id": item_id(url), "sourceId": source["id"], "title": title,
                "canonicalUrl": url, "publishedAt": iso(published) if published else None,
                "fetchedAt": iso(now), "language": source["language"], "topics": item_topics(url, source),
                "rights": {"title": True, "excerpt": source["rights"]["excerpts"], "image": False,
                           "licenseUrl": source["rights"]["licenseUrl"]},
                "eligibility": {"state": "eligible", "basis": "curated-source-scope",
                                "scope": source["eligibilityScope"], "reviewedAt": source["verifiedAt"]},
                "expiresAt": iso(now + timedelta(seconds=source["retentionSeconds"])), "image": None,
                "_guidHash": hashlib.sha256(guid[:4096].encode()).hexdigest()}
        if source["rights"]["excerpts"] and excerpt:
            item["excerpt"] = excerpt
        attribution = plain("; ".join(part for part in (attribution_raw, rights_raw) if part), 200)
        if attribution:
            item["attribution"] = attribution
        items.append(item)
    return items, held, deleted
