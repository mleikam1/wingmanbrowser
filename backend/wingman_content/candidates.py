"""Operator-only candidate inventory. Imported research never grants runtime rights."""
import csv
import hashlib
import io
import json
import os
import re
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

EXPECTED_CATEGORIES = {"Sports": 23, "Entertainment": 21, "Technology": 42,
                       "Fashion": 23, "Headlines": 16, "Business": 17, "Science": 19,
                       "Food": 20, "Health": 23, "Travel": 13}
BOOLEAN_COLUMNS = ("publication_country_verified", "all_criteria_verified",
                   "production_enabled", "image_display_enabled")
REQUIRED_COLUMNS = {"record_id", "category", "publisher", "feed_url", "source_url",
                    "terms_url", "notes", "moderation_note", "us_status", "traffic_status",
                    "traffic_evidence", "traffic_source", "live_feed_status", "image_availability",
                    "image_permission", "headline_permission", *BOOLEAN_COLUMNS}
PERMISSIONS = ("headlineLink", "excerpt", "articleImages", "branding", "fullText",
               "storageRedistribution")
MAX_INPUT_BYTES = 4 * 1024 * 1024


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode()
    fd, temporary = tempfile.mkstemp(prefix=".candidate-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path, default=None):
    path = Path(path)
    if not path.exists():
        return default
    if path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("Candidate document size limit")
    return json.loads(path.read_text(encoding="utf-8"))


def identity(prefix, value):
    return prefix + hashlib.sha256(value.encode()).hexdigest()[:24]


def explicit_boolean(value):
    if value.strip().lower() == "true":
        return True
    if value.strip().lower() == "false":
        return False
    return None  # Unknown research stays unknown; approval always requires `is True`.


def import_csv(data, prior=None, approved=None, filename="wingman_feed_candidates.csv",
               expected=True, checked_at=None):
    if not data or len(data) > MAX_INPUT_BYTES:
        raise ValueError("CSV size limit")
    text = data.decode("utf-8-sig", errors="strict")
    csv.field_size_limit(100000)
    reader = csv.DictReader(io.StringIO(text, newline=""), strict=True)
    columns = reader.fieldnames or []
    if len(columns) != len(set(columns)) or not REQUIRED_COLUMNS.issubset(columns):
        raise ValueError("Missing or duplicate CSV columns")
    rows = list(reader)
    if not rows or len(rows) > 5000:
        raise ValueError("Candidate row count limit")
    records, publishers, endpoints, seen = [], {}, {}, set()
    for number, raw in enumerate(rows, 2):
        if None in raw or any(value is None for value in raw.values()):
            raise ValueError("Malformed CSV row %d" % number)
        rid = raw["record_id"]
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", rid) or rid in seen:
            raise ValueError("Invalid or duplicate record ID at row %d" % number)
        seen.add(rid)
        if not raw["publisher"].strip() or not raw["feed_url"].strip() or raw["category"] not in EXPECTED_CATEGORIES:
            raise ValueError("Missing publisher/URL or unsupported category at row %d" % number)
        pid, eid = identity("publisher-", raw["publisher"]), identity("feed-", raw["feed_url"])
        publisher = publishers.setdefault(pid, {"id": pid, "label": raw["publisher"], "recordIds": []})
        endpoint = endpoints.setdefault(eid, {"id": eid, "originalUrl": raw["feed_url"],
                                              "recordIds": [], "publisherIds": []})
        publisher["recordIds"].append(rid)
        endpoint["recordIds"].append(rid)
        if pid not in endpoint["publisherIds"]:
            endpoint["publisherIds"].append(pid)
        typed = {key: explicit_boolean(raw[key]) for key in BOOLEAN_COLUMNS}
        records.append({"recordId": rid, "publisherId": pid, "endpointId": eid,
                        "category": raw["category"], "raw": raw, "parsedBooleans": typed,
                        "importIssues": ["unknown-boolean:" + key for key, value in typed.items() if value is None]})
    counts = {"records": len(records), "publishers": len(publishers), "literalFeedUrls": len(endpoints),
              "categories": dict(Counter(row["category"] for row in records))}
    if expected and counts != {"records": 217, "publishers": 201, "literalFeedUrls": 216,
                               "categories": EXPECTED_CATEGORIES}:
        raise ValueError("Input inventory changed: " + json.dumps(counts, sort_keys=True))
    digest = hashlib.sha256(data).hexdigest()
    prior = prior or {}
    history = list(prior.get("imports", []))
    if not any(entry["sha256"] == digest for entry in history):
        history.append({"sha256": digest, "filename": Path(filename).name, "bytes": len(data),
                        "importedAt": checked_at or utc_now(), "counts": counts})
    # Decisions live in a separate reviewed document, never this imported table.
    approved = approved or {"sources": []}
    for endpoint in endpoints.values():
        endpoint["existingExactSourceIds"] = sorted(s["id"] for s in approved["sources"]
                                                     if s["feedUrl"] == endpoint["originalUrl"])
    return {"schemaVersion": 1, "inputSha256": digest, "columns": columns, "imports": history,
            "counts": counts, "publishers": list(publishers.values()),
            "endpoints": list(endpoints.values()), "records": records}


def validate_inventory(value):
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise ValueError("Invalid candidate inventory")
    records = value.get("records", [])
    if not 1 <= len(records) <= 5000:
        raise ValueError("Invalid candidate records")
    endpoints = {entry["id"]: entry for entry in value.get("endpoints", [])}
    for record in records:
        if record["endpointId"] not in endpoints or record["raw"]["feed_url"] != endpoints[record["endpointId"]]["originalUrl"]:
            raise ValueError("Candidate endpoint association mismatch")
    return value


def reviews_for(record, reviews):
    decisions = []
    for decision in (reviews or {}).get("decisions", []):
        if record["recordId"] in decision.get("recordIds", []) and decision.get("feedUrl") == record["raw"]["feed_url"]:
            decisions.append(decision)
    return decisions


def permitted_url(value):
    try:
        parsed = urlsplit(value)
        return (parsed.scheme == "https" and bool(parsed.hostname) and parsed.port in (None, 443)
                and parsed.username is None and parsed.password is None and not parsed.fragment
                and not any(ord(c) < 33 or ord(c) == 127 for c in value) and "\\" not in value)
    except (TypeError, ValueError):
        return False


def promotion_patch(inventory, state, reviews, record_id, review_id, approved, now=None, compatibility_bytes=None):
    """Produce a reviewable addition only. Never enable or overwrite a source in place."""
    from .normalize import date_value
    now = now or datetime.now(timezone.utc)
    record = next((r for r in inventory["records"] if r["recordId"] == record_id), None)
    if record is None:
        raise ValueError("Unknown candidate record")
    decision = next((r for r in reviews_for(record, reviews) if r.get("reviewId") == review_id), None)
    if decision is None:
        raise ValueError("Review is not bound to the exact record and original endpoint")
    reviewed = date_value(decision.get("reviewedAt"))
    expires = date_value(decision.get("expiresAt"))
    if not reviewed or reviewed > now or (decision.get("expiresAt") is not None and (not expires or expires <= now)):
        raise ValueError("Missing, future or expired review")
    if decision.get("productionEnabled") is not True or decision.get("contentPolicy", {}).get("status") != "approved":
        raise ValueError("Explicit production and content-scope approval required")
    permissions = decision.get("permissions", {})
    source = decision.get("sourceConfig")
    if not isinstance(source, dict) or source.get("enabled") is not True:
        raise ValueError("A complete reviewed enabled source configuration is required")
    for key in ("headlineLink", "articleImages", "storageRedistribution"):
        grant = permissions.get(key, {})
        if (grant.get("status") != "approved" or not grant.get("scope")
                or not grant.get("evidenceUrls") or not all(permitted_url(url) for url in grant["evidenceUrls"])):
            raise ValueError("Required permission missing: " + key)
    for key, required in (("excerpt", source.get("rights", {}).get("excerpts") is True),
                          ("fullText", source.get("displayMode") == "sponsored-syndication"),
                          ("branding", source.get("branding") is not None)):
        if required and permissions.get(key, {}).get("status") != "approved":
            raise ValueError("Requested display permission missing: " + key)
    check = (state or {}).get("endpoints", {}).get(record["endpointId"], {})
    compatibility = checked_compatibility(decision, source, check, now, compatibility_bytes)
    if (check.get("status") not in ("working", "redirected") and compatibility is None) or not check.get("checkedAt"):
        raise ValueError("A successful exact-endpoint feed validation is required")
    if source.get("feedUrl") != check.get("requestUrl"):
        raise ValueError("Reviewed production URL differs from the validated endpoint")
    if (check.get("coverage") or {}).get("itemsWithImageCandidates", 0) < 1 and not (
            compatibility and compatibility.get("imageEligible")):
        raise ValueError("No article image candidate was observed; image rights alone are insufficient")
    action = "add-reviewed-source"
    for old in approved.get("sources", []):
        if source.get("id") == old.get("id") or source.get("feedUrl") == old.get("feedUrl"):
            if old == source:
                action = "already-reviewed-source"
            else:
                raise ValueError("Existing reviewed source must be reconciled, not duplicated or overwritten")
    return {"schemaVersion": 1, "action": action, "recordId": record_id,
            "reviewId": review_id, "inputSha256": inventory["inputSha256"], "checkedAt": check["checkedAt"],
            "createdAt": now.isoformat().replace("+00:00", "Z"), "source": source,
            "rawTechnicalStatus": check.get("status"), "compatibilityValidation": compatibility,
            "requiresRegistryRegeneration": True}


def checked_compatibility(decision, source, check, now, raw_bytes=None):
    """Operator-reviewed exception evidence; a runtime payload cannot grant it.

    Only the known NASA feed-level self-link repair has a compatibility contract.
    Raw malformed status remains visible and the byte-level probe binds evidence.
    """
    from .normalize import date_value
    value = decision.get("compatibilityValidation")
    if value is None:
        return None
    stamp = date_value(value.get("checkedAt"))
    raw_stamp = date_value(check.get("checkedAt"))
    exact_url = "https://science.nasa.gov/feed/photojournal/latest-content/"
    if (check.get("status") != "malformed" or source.get("id") != "nasa-photojournal"
            or source.get("feedUrl") != exact_url or check.get("requestUrl") != exact_url
            or value.get("feedUrl") != exact_url or value.get("sourceId") != source["id"]
            or value.get("compatibilityVersion") != "nasa-photojournal-self-link-v1"
            or source.get("feedCompatibility") != value.get("compatibilityVersion")
            or value.get("strictNormalizedParse") is not True
            or not stamp or not raw_stamp or stamp < raw_stamp or stamp > now
            or not re.fullmatch(r"[a-f0-9]{64}", value.get("originalSha256", ""))
            or value["originalSha256"] != check.get("rawSha256")
            or not re.fullmatch(r"[a-f0-9]{64}", value.get("normalizedSha256", ""))
            or value["normalizedSha256"] == value["originalSha256"]
            or type(value.get("normalizedItems")) is not int or not 1 <= value["normalizedItems"] <= 500):
        raise ValueError("Compatibility evidence is not bound to the reviewed NASA feed/version/bytes/time")
    images = value.get("imageEligible", [])
    reviewed = source.get("imagePolicy", {}).get("reviewedArticles", {})
    if not images or any(item.get("image") != reviewed.get(item.get("canonicalUrl")) for item in images):
        raise ValueError("Compatibility image evidence does not match the exact reviewed article associations")
    # Reproduce the existing narrow adapter and strict parse. A JSON boolean and
    # a plausible hash string alone cannot stand in for a validated raw feed.
    from .normalize import compatible_xml
    from .candidate_probe import inspect_feed
    if (not isinstance(raw_bytes, bytes) or len(raw_bytes) > 2 * 1024 * 1024
            or hashlib.sha256(raw_bytes).hexdigest() != value['originalSha256']):
        raise ValueError("Compatibility promotion requires matching bounded original feed bytes")
    normalized = compatible_xml(raw_bytes, source)
    if hashlib.sha256(normalized).hexdigest() != value['normalizedSha256']:
        raise ValueError("Compatibility normalization digest mismatch")
    _, coverage = inspect_feed(normalized, now)
    if coverage['items'] != value['normalizedItems']:
        raise ValueError("Compatibility strict parser count mismatch")
    return value


def build_report(inventory, state=None, reviews=None, approved=None, now=None):
    state, reviews, approved = state or {}, reviews or {}, approved or {"sources": []}
    rows = []
    totals = Counter()
    categories = {name: Counter() for name in EXPECTED_CATEGORIES}
    for record in inventory["records"]:
        check = state.get("endpoints", {}).get(record["endpointId"], {})
        decisions = reviews_for(record, reviews)
        exact = [s for s in approved["sources"] if s["feedUrl"] == record["raw"]["feed_url"]]
        status = check.get("status", "not-yet-checked")
        permission = decisions[-1].get("permissions", {}) if decisions else {}
        blockers = []
        if status not in ("working", "redirected"):
            blockers.append(check.get("reason", "Endpoint not checked"))
        if not decisions:
            blockers.append("No exact-endpoint commercial display/content review")
        for key in ("headlineLink", "excerpt", "articleImages", "storageRedistribution"):
            if permission.get(key, {}).get("status") != "approved":
                blockers.append(key + ": " + permission.get(key, {}).get("status", "unreviewed"))
        active = [s["id"] for s in exact if s.get("enabled") is True]
        if not active:
            blockers.append("Not in reviewed production configuration")
        row = {"recordId": record["recordId"], "publisherId": record["publisherId"],
               "publisher": record["raw"]["publisher"], "category": record["category"],
               "endpointId": record["endpointId"], "originalUrl": record["raw"]["feed_url"],
               "requestUrl": check.get("requestUrl"), "resolvedUrl": check.get("resolvedUrl"),
               "checkedAt": check.get("checkedAt"), "status": status, "reason": check.get("reason"),
               "httpStatus": check.get("httpStatus"), "format": check.get("format"),
               "coverage": check.get("coverage"), "nextCheckAt": check.get("nextCheckAt"),
               "originalResearch": record["raw"], "parsedBooleans": record["parsedBooleans"],
               "reviews": decisions, "existingExactSourceIds": [s["id"] for s in exact],
               "compatibilityValidation": decisions[-1].get("compatibilityValidation") if decisions else None,
               "productionEnabled": bool(active), "productionSourceIds": active,
               "imageDisplayEnabled": any(s.get("rights", {}).get("images") is True for s in exact if s.get("enabled") is True),
               "brandingStatus": "approved-logo" if any(s.get("branding") for s in exact) else "initials-fallback",
               "visibleStoryCount": None, "visibleImageAndExcerptCount": None,
               "visibleCoverageReason": "Requires actual normalized snapshot, decoded image and client display evidence",
               "blockers": blockers}
        rows.append(row)
        for count in (totals, categories[record["category"]]):
            count["candidateRows"] += 1
            count[status] += 1
            count["checkedRows" if check.get("checkedAt") else "uncheckedRows"] += 1
            count["productionRows" if active else "heldRows"] += 1
    endpoints = state.get("endpoints", {})
    unique = {"checked": sum(bool(s.get("checkedAt")) for s in endpoints.values()),
              "technicallyWorking": sum(s.get("status") in ("working", "redirected") for s in endpoints.values()),
              "statuses": dict(Counter(endpoints.get(e["id"], {}).get("status", "not-yet-checked") for e in inventory["endpoints"]))}
    category_report = {}
    for category, counters in categories.items():
        members = [row for row in rows if row['category'] == category]
        category_endpoints = {row['endpointId'] for row in members}
        active_sources = {sid for row in members for sid in row['productionSourceIds']}
        category_report[category] = dict(counters,
            uniquePublishers=len({row['publisherId'] for row in members}), uniqueEndpoints=len(category_endpoints),
            checkedEndpoints=sum(bool(endpoints.get(eid, {}).get('checkedAt')) for eid in category_endpoints),
            technicallyWorkingEndpoints=sum(endpoints.get(eid, {}).get('status') in ('working', 'redirected') for eid in category_endpoints),
            productionSources=len(active_sources), reviewedRows=sum(bool(row['reviews']) for row in members),
            approvedLogoSources=len({sid for row in members if row['brandingStatus'] == 'approved-logo' for sid in row['productionSourceIds']}),
            initialsFallbackSources=len({sid for row in members if row['brandingStatus'] == 'initials-fallback' for sid in row['productionSourceIds']}),
            visibleImageAndExcerptStories=None)
    imported_ids = {s['id'] for s in approved['sources'] if s.get('candidateRecordId') in {r['recordId'] for r in inventory['records']}}
    return {"schemaVersion": 1, "generatedAt": now or utc_now(), "inputSha256": inventory["inputSha256"],
            "inventory": inventory["counts"], "uniqueEndpointChecks": unique,
            "productionInventory": {"newCandidateSourceIds": sorted(imported_ids),
                                    "preservedExistingSourceIds": [s['id'] for s in approved['sources'] if s['id'] not in imported_ids]},
            "totals": dict(totals, reviewedRows=sum(bool(row['reviews']) for row in rows),
                           unreviewedRows=sum(not row['reviews'] for row in rows)),
            "categories": category_report, "records": rows,
            "scope": "Operator source-validation observations only; no app-user activity or automatic production activation."}


def report_markdown(report):
    lines = ["# Feed candidate validation", "", "Generated " + report["generatedAt"], "",
             "%d records; %d publisher labels; %d literal endpoints. %d endpoints checked, %d technically working." % (
                 report["inventory"]["records"], report["inventory"]["publishers"], report["inventory"]["literalFeedUrls"],
                 report["uniqueEndpointChecks"]["checked"], report["uniqueEndpointChecks"]["technicallyWorking"]),
             "", "Availability, rights, U.S. qualification, traffic and production activation are separate facts.",
             "Image-candidate counts are metadata observations, not decoded/rights-approved photos or visible cards.", "",
             "| Record | Category | Publisher | Resolved or attempted endpoint | Status / UTC check | Article / excerpt / image candidates | Rights / policy / branding | Production / blockers |",
             "|---|---|---|---|---|---|---|---|"]
    def safe(value):
        text = str(value or "—").replace("\n", " ").replace("\r", " ").replace("<", "&lt;")
        return re.sub(r"([\\\[\]()`*_!|])", r"\\\1", text)
    for row in report["records"]:
        coverage = row["coverage"] or {}
        counts = "/".join(str(coverage.get(k, "—")) for k in ("items", "itemsWithExcerpts", "itemsWithImageCandidates"))
        review = row["reviews"][-1] if row["reviews"] else {}
        permissions = review.get("permissions", {})
        rights = "; ".join(key + "=" + permissions.get(key, {}).get("status", "unreviewed") for key in PERMISSIONS)
        evidence = sorted({url for grant in permissions.values() for url in grant.get("evidenceUrls", [])})
        rights += "; policy=" + review.get("contentPolicy", {}).get("status", "unreviewed")
        rights += "; " + row["brandingStatus"]
        if evidence:
            rights += "; evidence: " + ", ".join(evidence)
        if row.get("compatibilityValidation"):
            rights += "; separately reproduced pinned compatibility adapter (raw feed still malformed)"
        lines.append("| " + " | ".join(safe(v) for v in (row["recordId"], row["category"], row["publisher"],
                     row["resolvedUrl"] or row["requestUrl"] or row["originalUrl"],
                     row["status"] + " / " + (row["checkedAt"] or "not checked"), counts, rights,
                     ("enabled" if row["productionEnabled"] else "held") + ": " + "; ".join(row["blockers"]))) + " |")
    return "\n".join(lines) + "\n"
