"""Provider-neutral ingestion and common snapshot publication."""
import hashlib
import re
from abc import ABC, abstractmethod
from datetime import datetime, timedelta, timezone
from .config import registry
from .fetch import FetchError, SecureFeedFetcher
from .normalize import date_value, iso, parse_feed, canonical_url, item_id, matches_topic_scope
from .store import encode, WriterLeaseError

MAX_SHARED_ITEMS = 300
MAX_SNAPSHOT_BYTES = 512 * 1024
MAX_FAILURES = 12
NORMALIZATION_VERSION = 7
MAX_REVOCATIONS = 5000  # Matches the client envelope limit.


class NewsProvider(ABC):
    @abstractmethod
    def refresh(self, source, prior, now):
        """Return validated normalized source state; never accepts user context."""


class CompositeNewsProvider(NewsProvider):
    """Exactly one adapter per source; provider absence never disables RSS."""
    def __init__(self, rss_provider, currents_provider=None):
        self.rss_provider, self.currents_provider = rss_provider, currents_provider

    def refresh(self, source, prior, now):
        if source.get('providerId', 'rss') == 'rss':
            return self.rss_provider.refresh(source, prior, now)
        if source.get('providerId') != 'currents':
            raise ValueError('unreviewed-provider')
        if self.currents_provider is not None:
            return self.currents_provider.refresh(source, prior, now)
        return dict(prior, status='cached' if prior.get('lastSuccessAt') else 'not-configured',
                    error='provider-not-configured', lastHttpStatus=None,
                    nextRefreshAt=iso(now + timedelta(minutes=30)))

    def bind_writer_guard(self, guard):
        gateway = getattr(self.currents_provider, 'gateway', None)
        if gateway is not None:
            gateway.before_request = guard


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
        if source.get('providerId', 'rss') != 'rss':
            # A miswired caller cannot turn the legacy fetcher into an API path
            # that bypasses Currents' durable reservation gateway.
            raise ValueError('rss-provider-mismatch')
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
            delay = delay_seconds(dict(response.headers, **{'cache-control': cache_control}), now, source['minRefreshSeconds'])
            raise FetchError("source-cache-prohibited", str(delay) if delay is not None else '9999999999',
                             http_status=response.status)
        if response.status == 304:
            if not prior.get("lastSuccessAt") or not compatible:
                raise FetchError("unconditional-304")
            items, held, deleted = prior.get("items", []), {"count": prior.get("heldCount", 0),
                "reasons": prior.get("heldReasons", {}), "examples": prior.get("heldExamples", [])}, []
            # Successful revalidation updates freshness, never publication date.
            items = [dict(item, fetchedAt=iso(now),
                          expiresAt=iso(now + timedelta(seconds=source["retentionSeconds"]))) for item in items]
            held.update(prior.get('parseDiagnostics', {}))
        else:
            try:
                items, held, deleted = parse_feed(response.body, source, now, self.destination_policy)
            except Exception as exc:
                raise FetchError('invalid-feed', http_status=response.status) from exc
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
                'lastParsedAt': (prior.get('lastParsedAt') or prior.get('lastSuccessAt')) if response.status == 304 else iso(now),
                "nextRefreshAt": iso(now + timedelta(seconds=delay)) if delay is not None else None,
                "refreshSuspended": delay is None,
                "failures": 0, "error": None, "heldCount": held["count"],
                "heldReasons": held["reasons"], "heldExamples": held["examples"], "lastHttpStatus": response.status,
                "parseDiagnostics": {key: held.get(key, 0) for key in
                    ('parsedEntries', 'textEligible', 'topicMatched', 'imagePermitted')},
                "optionalFieldReasons": held.get('optionalFieldReasons', prior.get('optionalFieldReasons', {})),
                "revokedItemIds": sorted(revoked), "status": "fresh"}


def is_unexpired(item, now):
    expires = date_value(item.get("expiresAt"))
    if item.get('providerId') == 'currents':
        fetched = date_value(item.get('fetchedAt'))
        if fetched is None or fetched > now + timedelta(minutes=5):
            return False
        expires = min(expires, fetched + timedelta(hours=24)) if expires else None
    return expires is not None and expires > now


def item_current(item, now):
    published = date_value(item.get("publishedAt"))
    return published is None or published >= now - timedelta(days=30)


def diverse_inventory(items, topics):
    """Round-robin categories and prefer less represented publishers per turn.

    Sorting once by publication preserves recency within each publisher. This
    ordering is applied before either the item or byte budget is consumed.
    """
    items = sorted(items, key=lambda item: (item.get('publishedAt') or '', item['id']), reverse=True)
    buckets = {topic: [item for item in items if topic in item.get('topics', [])] for topic in topics}
    buckets['_other'] = [item for item in items if not any(t in topics for t in item.get('topics', []))]
    selected, seen, publisher_counts = [], set(), {}
    while len(selected) < MAX_SHARED_ITEMS:
        progressed = False
        for rows in buckets.values():
            rows[:] = [item for item in rows if item['id'] not in seen]
            if not rows:
                continue
            item = min(rows, key=lambda row: publisher_counts.get(row.get('publisherId', row['sourceId']), 0))
            seen.add(item['id'])
            selected.append(item)
            publisher = item.get('publisherId', item['sourceId'])
            publisher_counts[publisher] = publisher_counts.get(publisher, 0) + 1
            progressed = True
            if len(selected) == MAX_SHARED_ITEMS:
                break
        if not progressed:
            break
    return selected


def bounded_public_item(item):
    """Keep the typed app envelope finite even when old stored fields are huge."""
    fields = ('id', 'sourceId', 'providerId', 'providerArticleId', 'publisherId', 'publisherName',
              'providerCategories', 'providerAttribution', 'title', 'canonicalUrl', 'originalUrl',
              'outboundUrl', 'publishedAt', 'fetchedAt', 'expiresAt', 'updatedAt', 'language',
              'topics', 'rights', 'eligibility', 'image', 'excerpt', 'excerptProvenance',
              'attribution', 'author', 'syndicatedArticle', 'region')
    result = {key: item[key] for key in fields if key in item}
    for key, limit in (('excerpt', 1600), ('attribution', 500), ('author', 200),
                       ('publisherName', 120), ('publisherId', 253), ('providerArticleId', 120)):
        if key in result and isinstance(result[key], str) and len(result[key]) > limit:
            result[key] = result[key][:limit]
    # An overlong optional blob cannot evict all other publishers/categories.
    for key in ('image', 'excerptProvenance', 'providerAttribution'):
        if key in result and len(encode(result[key])) > 16384:
            result.pop(key)
    return result


def public_availability(state, status):
    """Small reader-facing state, never operational usage or query diagnostics."""
    if status == 'revoked':
        return 'revoked'
    error = state.get('error')
    if error in ('provider-not-configured', 'currents-unconfigured', 'currents-setup-required',
                 'authentication-paused', 'http-401', 'http-403'):
        return 'configuration'
    if error in ('http-429', 'provider-wait', 'local-budget-exhausted', 'provider-quota-reserve',
                 'supplement-budget-reserve'):
        return 'quota-paused'
    if error in ('query-held', 'http-400') or state.get('refreshSuspended'):
        return 'policy-held'
    if state.get('status') == 'valid-empty':
        return 'valid-empty'
    return status if status in ('cached', 'fresh', 'unavailable') else 'unavailable'


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
        if not source["enabled"] or not source['rights'].get('titles') or state.get("sourceRevoked"):
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
                        lastSuccessAt=state.get("lastSuccessAt"), nextRefreshAt=state.get("nextRefreshAt"),
                        availability=public_availability(state, status))
        for key in ('providerId', 'providerAttribution'):
            if key in source:
                metadata[key] = source[key]
        sources.append(metadata)
        if status in ("revoked", "unavailable"):
            continue
        for item in state.get("items", []):
            if item["id"] in revoked or not is_unexpired(item, now) or not item_current(item, now):
                continue
            # Config changes cannot be bypassed by cached normalization.
            if not canonical_url(item["canonicalUrl"], source):
                continue
            if (not matches_topic_scope(item.get('title', ''), item.get('excerpt', ''), source)
                    or (source.get('requiresAttribution') and not item.get('attribution'))):
                continue
            candidate = bounded_public_item(item)
            candidate["rights"] = {"title": True, "excerpt": source["rights"]["excerpts"],
                                   "image": source['rights']['images'], "licenseUrl": source["rights"]["licenseUrl"]}
            if not source["rights"]["excerpts"]:
                candidate.pop("excerpt", None)
                candidate.pop("excerptProvenance", None)
            from .media import accepts_image
            if not accepts_image(candidate.get('image'), source):
                candidate['image'] = None
            candidate['rights']['image'] = candidate.get('image') is not None
            if source.get('displayMode', 'publisher-link') != 'sponsored-syndication':
                candidate.pop('syndicatedArticle', None)
            # Stable URL identity wins deterministically; distinct articles with
            # the same headline are never collapsed.
            old = by_url.get(candidate['canonicalUrl'])
            # The same article may appear in a broad feed and its reviewed
            # photo-specific feed. Keep the complete approved representation;
            # never combine permissions or image fields from different sources.
            if old is None:
                by_url[candidate['canonicalUrl']] = candidate
            else:
                # Merge only membership, preserving one complete rights/assets
                # representation. Never graft one provider's image onto another.
                winner = candidate if candidate.get('image') and not old.get('image') else old
                compatible = (old.get('providerId', 'rss') == candidate.get('providerId', 'rss') and
                              old.get('rights') == candidate.get('rights'))
                if compatible:
                    winner['topics'] = sorted(set(old.get('topics', [])) | set(candidate.get('topics', [])))
                if compatible and old.get('providerId') == candidate.get('providerId') == 'currents':
                    winner['providerCategories'] = sorted(set(old.get('providerCategories', [])) |
                                                          set(candidate.get('providerCategories', [])))
                by_url[candidate['canonicalUrl']] = winner
    revoked_sources = sorted(set(revoked_sources) | set((prior_snapshot or {}).get("revokedSourceIds", [])))
    items = [item for item in by_url.values() if item["id"] not in revoked
             and item["sourceId"] not in revoked_sources]
    topics = list(dict.fromkeys(topic for source in config['sources'] for topic in source['topics']))
    items = diverse_inventory(items, topics)
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
    # Reserve balanced order first, then add records that fit. A large feature
    # is skipped individually rather than consuming the remaining categories.
    result['items'] = []
    remaining = MAX_SNAPSHOT_BYTES - len(encode(result))
    for item in items if not result.get('recoveryRequired') else []:
        size = len(encode(item)) + (1 if result['items'] else 0)
        if size <= remaining:
            result['items'].append(item)
            remaining -= size
    if len(encode(result)) > MAX_SNAPSHOT_BYTES:
        raise ValueError("Snapshot metadata/revocation size limit")
    result["snapshotId"] = hashlib.sha256(encode(result)).hexdigest()[:32]
    return result


def ingest(config, store, provider, now=None, media_fetcher=None):
    # All programmatic callers share the same cross-process publication lock.
    # Acquiring it precedes both the content read and every provider operation.
    with store.writer() as writer_guard:
        if hasattr(provider, 'bind_writer_guard'):
            provider.bind_writer_guard(writer_guard)
        try:
            return _ingest(config, store, provider, now, media_fetcher, writer_guard)
        finally:
            if hasattr(provider, 'bind_writer_guard'):
                provider.bind_writer_guard(None)


def _ingest(config, store, provider, now=None, media_fetcher=None, writer_guard=lambda: None):
    live_clock = now is None
    now = now or datetime.now(timezone.utc)
    prior = store.read() or {"states": {}, "snapshot": {}}
    states, report = {}, []
    for source in config["sources"]:
        source_now = datetime.now(timezone.utc) if live_clock else now
        previous = prior.get("states", {}).get(source["id"], {})
        state = dict(previous)
        due = date_value(state.get("nextRefreshAt"))
        requested = False
        action = ("disabled" if not source["enabled"] else "source-revoked" if state.get("sourceRevoked")
                  else "suspended" if state.get("refreshSuspended") else "not-due")
        if source["enabled"] and not state.get("sourceRevoked") and not state.get("refreshSuspended") and (due is None or source_now >= due):
            requested = True
            try:
                writer_guard()
                state = provider.refresh(source, previous, source_now)
                writer_guard()
                action = "http-%d" % state["lastHttpStatus"] if state.get('lastHttpStatus') else state.get('error') or state.get('status', 'not-due')
            except WriterLeaseError:
                raise
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
                state['lastHttpStatus'] = getattr(exc, 'http_status', None)
                if reason == "source-cache-prohibited":
                    # Evict this representation. Cache instructions are temporary
                    # storage rules, not a legal withdrawal of the article ID.
                    state["items"] = []
                    state.pop('etag', None)
                    state.pop('lastModified', None)
                    state.pop('normalizationKey', None)
                action = reason
        # Do not retain bodies, HTML, image URLs or expired normalized records.
        state["items"] = [item for item in state.get("items", []) if is_unexpired(item, source_now)]
        if 'currentsPools' in state:
            state['currentsPools'] = {key: [item for item in items if is_unexpired(item, source_now)]
                                     for key, items in state['currentsPools'].items()}
        if not source['enabled'] or not source['rights'].get('titles') or state.get('sourceRevoked'):
            state['items'] = []
            if 'currentsPools' in state:
                state['currentsPools'] = {}
        from .diagnostics import source_diagnostics
        state['diagnostics'] = source_diagnostics(source, state, source_now, action, requested,
                                                  was_due=due is None or source_now >= due)
        states[source["id"]] = state
        report.append({"sourceId": source["id"], "action": action, "items": len(state.get("items", [])),
                       "held": state.get("heldCount", 0), "heldReasons": state.get("heldReasons", {}),
                       "heldExamples": state.get("heldExamples", []), "nextRefreshAt": state.get("nextRefreshAt"),
                       'diagnostics': state['diagnostics']})
        if source.get('providerId') == 'currents':
            report[-1]['jobReport'] = state.get('jobReport', [])
    snapshot = public_snapshot(config, states, datetime.now(timezone.utc) if live_clock else now, prior.get("snapshot"))
    if snapshot.get('recoveryRequired'):
        for state in states.values():
            state.update(sourceRevoked=True, items=[], revokedItemIds=[])
    from .media import ingest_media
    writer_guard()
    media, media_report = ingest_media(snapshot, config, prior.get('media', {}),
                                       datetime.now(timezone.utc) if live_clock else now, media_fetcher,
                                       cursor=prior.get('mediaCursor', 0), before_request=writer_guard)
    writer_guard()
    store.write({"schemaVersion": 1, "states": states, "snapshot": snapshot,
                 "media": media, "mediaReport": media_report,
                 "mediaCursor": media_report[-1]['scheduler']['nextCursor']})
    return snapshot, report
