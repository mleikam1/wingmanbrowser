"""Reviewed article media, ingested once; GET requests never fetch publishers.

The private bundle holds only cache-permitted checked bytes. NewsUSA no-store
photos remain native transient data and can never enter this shared media store.
"""
import base64
import hashlib
import io
import json
import re
import time
import warnings
from datetime import timedelta
from urllib.parse import parse_qsl, unquote, urlsplit
from PIL import Image
from .fetch import FetchError, SecureFeedFetcher, configured_url
from .normalize import date_value, iso, item_id

IMAGE_TYPES = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}
MAX_IMAGE_BYTES = 1024 * 1024
MAX_MEDIA_BYTES = 1024 * 1024  # Base64 plus text/state fits the atomic 4 MiB bundle.
MAX_MEDIA_BATCH = 24
IMAGE_FIELDS = ("schemaVersion", "url", "articleUrl", "sourceId", "credit", "caption",
                "licenseUrl", "licenseLabel", "basis", "width", "height")


def image_key(image):
    # Matches LiveArticleImage.cacheKey (JSON field order is part of v1).
    fields = {}
    for key in IMAGE_FIELDS:
        fields[key] = image.get(key)
        if key == "sourceId" and image.get("articleId") is not None:
            fields["articleId"] = image["articleId"]
    return hashlib.sha256(json.dumps(fields,
                         ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def validate_image_policy(source):
    policy = source["imagePolicy"]
    if policy.get("kind") not in {"syndicated-feed-thumbnail", "syndicated-article-photo", "reviewed-article-image"}:
        raise ValueError("Unknown image contract")
    for key in ("maximumWidth", "maximumHeight"):
        if type(policy.get(key)) is not int or not 1 <= policy[key] <= 2048:
            raise ValueError("Invalid image dimensions")
    if not source["rights"]["images"] or not all(policy.get(k) for k in ("licenseUrl", "licenseLabel", "credit")):
        raise ValueError("Missing image reuse evidence")
    hosts, paths = policy.get("allowedHosts", []), policy.get("pathPrefixes", [])
    if (not 1 <= len(hosts) <= 10 or not 1 <= len(paths) <= 10 or
            any(not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+", h) for h in hosts) or
            any(not isinstance(p, str) or not p.startswith("/") or len(p) > 256 or
                re.search(r"[\x00-\x20%\\?#]", p) or ".." in p for p in paths)):
        raise ValueError("Invalid image destinations")
    if policy["kind"] == "syndicated-feed-thumbnail" and (
            policy["maximumWidth"] != 90 or policy["maximumHeight"] != 90):
        raise ValueError("The reviewed thumbnail contract is exactly 90 by 90")
    if policy["kind"] == "syndicated-article-photo" and source.get("displayMode") != "sponsored-syndication":
        raise ValueError("Article photos require the separate complete syndication adapter")
    if policy["kind"] == "reviewed-article-image":
        rows = policy.get("reviewedArticles", {})
        if not isinstance(rows, dict) or not 1 <= len(rows) <= 200:
            raise ValueError("Missing individual article image reviews")
        for article, image in rows.items():
            if image.get("articleUrl") != article or image.get("articleId") != item_id(article) or not accepts_image(image, dict(source, enabled=True)):
                raise ValueError("Invalid individually reviewed image")


def accepts_image_url(url, source):
    policy = source.get("imagePolicy") or {}
    try:
        parsed = urlsplit(url)
        if (len(url) > 4096 or re.search(r"[\x00-\x20\\]", url) or parsed.scheme != "https" or
                parsed.hostname not in policy.get("allowedHosts", []) or parsed.username is not None or
                parsed.password is not None or parsed.port not in (None, 443) or parsed.fragment):
            return False
        path = unquote(parsed.path)
        if re.search(r"[\x00-\x1f\\%]", path) or any(p in (".", "..") for p in path.split("/")):
            return False
        if not any(path == p or path.startswith(p if p.endswith("/") else p + "/") for p in policy.get("pathPrefixes", [])):
            return False
        if policy.get("kind") == "reviewed-article-image":
            return any(row.get("url") == url for row in policy.get("reviewedArticles", {}).values())
        query = parse_qsl(parsed.query, keep_blank_values=True, max_num_fields=5)
        return len({k for k, _ in query}) == len(query) and all(
            k in policy.get("allowedQueryKeys", []) and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", v) for k, v in query)
    except (ValueError, TypeError):
        return False


def accepts_image(image, source):
    policy = source.get("imagePolicy") or {}
    if (not source.get("enabled") or not source["rights"].get("images") or
            not isinstance(image, dict) or image.get("schemaVersion") != 1 or
            image.get("sourceId") != source["id"] or image.get("basis") != policy.get("kind") or
            not accepts_image_url(image.get("url", ""), source)):
        return False
    if policy.get("kind") == "reviewed-article-image":
        pinned = policy.get("reviewedArticles", {}).get(image.get("articleUrl"))
        return (pinned is not None and image.get('articleId') == pinned.get('articleId') and
                all(image.get(k) == pinned.get(k) for k in IMAGE_FIELDS))
    if any(image.get(key) != policy.get(key) for key in ("licenseUrl", "licenseLabel", "credit")):
        return False
    w, h = image.get("width"), image.get("height")
    if type(w) is not int or type(h) is not int:
        return False
    return (w == h == 90 if policy.get("kind") == "syndicated-feed-thumbnail" else
            0 <= w <= policy.get("maximumWidth", 0) and 0 <= h <= policy.get("maximumHeight", 0))


class SecureImageFetcher(SecureFeedFetcher):
    accepted_types = set(IMAGE_TYPES)
    accept = "image/jpeg, image/png, image/webp"

    def checked_url(self, url, source):
        if not accepts_image_url(url, source):
            raise FetchError("unapproved-image-destination")
        return configured_url(url, dict(source, feedRedirectHosts=source["imagePolicy"]["allowedHosts"]))

    def fetch_image(self, image, source):
        if not accepts_image(image, source):
            raise FetchError("unapproved-image")
        return self.fetch(dict(source, feedUrl=image["url"]))


def check_image(data, image, mime, source):
    if not data or len(data) > MAX_IMAGE_BYTES or mime not in IMAGE_TYPES:
        raise ValueError("image-size-or-type")
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data)) as decoded:
            w, h = decoded.size
            policy = source["imagePolicy"]
            if (decoded.format != IMAGE_TYPES[mime] or getattr(decoded, "n_frames", 1) != 1 or
                    min(w, h) < 16 or w > policy["maximumWidth"] or h > policy["maximumHeight"] or
                    w * h > 4 * 1024 * 1024 or
                    (image["width"] and w != image["width"]) or (image["height"] and h != image["height"])):
                raise ValueError("image-format-or-dimensions")
            decoded.verify()
        with Image.open(io.BytesIO(data)) as decoded:
            decoded.load()


def cache_ttl(headers):
    cache = headers.get("cache-control", "")
    if (re.search(r"(?:^|,)\s*(?:no-store|private|no-cache)(?:\s*(?:,|=|$))", cache, re.I) or
            "no-cache" in headers.get("pragma", "").lower()):
        return 0
    # Shared storage requires explicit cache permission; ambiguous responses are held.
    ages = re.findall(r"(?:^|,)\s*(?:s-maxage|max-age)\s*=\s*\"?(\d+)", cache, re.I)
    if not ages or any(len(n) > 10 for n in ages):
        return 0
    age = headers.get("age", "0")
    if not age.isdigit() or len(age) > 10:
        return 0
    return max(0, min(1800, min(map(int, ages)) - int(age)))


def ingest_media(snapshot, config, prior, now, fetcher=None, cursor=0, before_request=None):
    """Bounded common source interleave. No user or topic inputs; private report only."""
    fetcher = fetcher or SecureImageFetcher()
    sources = {s["id"]: s for s in config["sources"]}
    items = [i for i in snapshot["items"] if i.get("image") and i["sourceId"] in sources and
             accepts_image(i["image"], sources[i["sourceId"]])]
    groups = {sid: [i for i in items if i["sourceId"] == sid] for sid in sources}
    queue = [rows[index] for index in range(max(map(len, groups.values()), default=0))
             for rows in groups.values() if index < len(rows)]
    if queue:
        cursor = cursor % len(queue)
        indexed = list(enumerate(queue))
        indexed = indexed[cursor:] + indexed[:cursor]
    else:
        indexed = []
    media, report, used, attempts = {}, [], 0, 0
    next_cursor = cursor
    deadline = time.monotonic() + 45
    for position, item in indexed:
        image, source = item["image"], sources[item["sourceId"]]
        key = image_key(image)
        old = prior.get(key, {})
        # Never persist full-article no-store source imagery, even on a misleading
        # future cache header; this source's reviewed delivery is transient only.
        if source.get("displayMode") == "sponsored-syndication":
            report.append({"itemId": item["id"], "state": "native-transient-only"})
            continue
        record = None
        if date_value(old.get("expiresAt")) and date_value(old["expiresAt"]) > now:
            record = old
        elif attempts < MAX_MEDIA_BATCH and time.monotonic() < deadline:
            attempts += 1
            next_cursor = (position + 1) % len(queue)
            try:
                if before_request:
                    before_request()
                response = fetcher.fetch_image(image, source)
                ttl = cache_ttl(response.headers)
                if response.status != 200 or not ttl:
                    raise ValueError("shared-storage-not-permitted")
                mime = response.headers.get("content-type", "").split(";")[0].lower().strip()
                check_image(response.body, image, mime, source)
                expires = min(now + timedelta(seconds=ttl), date_value(item["expiresAt"]))
                record = {"data": base64.b64encode(response.body).decode(), "mime": mime,
                          "sha256": hashlib.sha256(response.body).hexdigest(), "bytes": len(response.body),
                          "expiresAt": iso(expires)}
            except (FetchError, ValueError, OSError) as exc:
                report.append({"itemId": item["id"], "state": getattr(exc, "reason", str(exc))[:100]})
        if record and used + record.get("bytes", MAX_MEDIA_BYTES + 1) <= MAX_MEDIA_BYTES:
            media[key] = record
            used += record["bytes"]
            report.append({"itemId": item["id"], "state": "available"})
        elif record:
            report.append({"itemId": item["id"], "state": "media-byte-budget"})
        else:
            report.append({"itemId": item["id"], "state": "not-available-this-batch"})
    report.append({'scheduler': {'eligible': len(queue), 'attempted': attempts,
                                'available': len(media), 'bytes': used, 'nextCursor': next_cursor,
                                'maximumAttempts': MAX_MEDIA_BATCH, 'maximumBytes': MAX_MEDIA_BYTES}})
    return media, report


def media_response(bundle, key, now):
    if not re.fullmatch(r"[a-f0-9]{64}", key):
        return None
    snapshot = bundle.get("snapshot", {})
    revoked_sources, revoked_items = snapshot.get("revokedSourceIds", []), snapshot.get("revokedItemIds", [])
    items = [i for i in snapshot.get("items", []) if i.get("image") and image_key(i["image"]) == key and
               i["sourceId"] not in revoked_sources and i["id"] not in revoked_items and
               (not date_value(i.get('publishedAt')) or date_value(i['publishedAt']) >= now - timedelta(days=30)) and
               (date_value(i.get("expiresAt")) or now) > now]
    if not items:
        return None
    record = bundle.get("media", {}).get(key, {})
    expires = date_value(record.get("expiresAt"))
    if not expires or expires <= now:
        return None
    try:
        data = base64.b64decode(record["data"], validate=True)
        if (len(data) != record["bytes"] or len(data) > MAX_IMAGE_BYTES or
                hashlib.sha256(data).hexdigest() != record["sha256"] or record["mime"] not in IMAGE_TYPES):
            return None
        # A client may retain checked bytes only while both media and its story
        # remain current. Cap the common response at the native 30-minute window.
        deadlines = [expires, now + timedelta(minutes=30)]
        for item in items:
            deadlines.append(date_value(item["expiresAt"]))
            published = date_value(item.get("publishedAt"))
            if published:
                deadlines.append(published + timedelta(days=30))
        ttl = int((min(deadlines) - now).total_seconds())
        return (data, record["mime"], ttl) if ttl > 0 else None
    except (KeyError, ValueError, TypeError):
        return None
