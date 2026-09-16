"""Bounded common-source diagnostics; no reader state or publisher requests."""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone

from .config import registry
from .normalize import date_value, iso

COUNTS = ('parsedEntries', 'textEligible', 'topicMatched', 'imagePermitted')
TOPICS = ('headlines', 'sports', 'entertainment', 'business', 'technology',
          'science', 'food', 'health', 'fashion', 'travel', 'environment')


def reason_counts(value):
    return {key: min(500, max(0, count)) for key, count in list((value or {}).items())[:32]
            if isinstance(key, str) and re.fullmatch(r'[a-z][a-z0-9-]{0,79}', key)
            and type(count) is int}


def source_diagnostics(source, state, now, action, requested, was_due):
    """Counts describe the last successful parse; outcomes the latest check.

    A cached source can have useful parse counts after an unsuccessful attempt.
    The separate timestamps make this explicit instead of inventing zero supply.
    """
    old = state.get('diagnostics', {})
    items = state.get('items', [])
    counts = state.get('parseDiagnostics', {})
    parsed = counts.get('parsedEntries', len(items) + state.get('heldCount', 0))
    status = state.get('lastHttpStatus')
    if not status and requested and re.fullmatch(r'http-[1-5][0-9]{2}', action):
        status = int(action[5:])
    failed = requested and not action.startswith('http-2') and action != 'http-304'
    parser_error = 'invalid-feed' if requested and action == 'invalid-feed' else None
    outcome = ('not-modified' if action == 'http-304' else
               'fresh' if action == 'http-200' and items else
               'empty' if action == 'http-200' and parsed == 0 else
               'content-held' if action == 'http-200' else
               'parse-failure' if parser_error else
               'cache-prohibited' if action == 'source-cache-prohibited' else
               'revoked' if action in ('disabled', 'source-revoked') else
               'publisher-hold' if action == 'suspended' else
               'not-configured' if action == 'not-yet-checked' else
               'transport-failure' if failed else action)
    newest = max((item.get('publishedAt') for item in items if date_value(item.get('publishedAt'))), default=None)
    result = {'schemaVersion': 1, 'checkedAt': iso(now),
              'attemptedAt': iso(now) if requested else old.get('attemptedAt', state.get('fetchedAt')),
              'lastSuccessAt': state.get('lastSuccessAt'), 'nextDueAt': state.get('nextRefreshAt'),
              'outcome': outcome, 'httpStatus': status,
              'lastAttemptOutcome': outcome if requested else old.get('lastAttemptOutcome'),
              'lastError': action if failed else None if requested else old.get('lastError', state.get('error')),
              'transportError': action if failed and not parser_error and action != 'source-cache-prohibited' else None,
              'parserError': parser_error,
              'configured': True, 'enabled': source.get('enabled') is True,
              'due': was_due and source.get('enabled') is True,
              'deferred': False, 'requested': requested,
              'fetched': requested and status in (200, 304),
              'parsedEntries': parsed,
              'textEligible': counts.get('textEligible', len(items)),
              'topicMatched': counts.get('topicMatched', len(items)),
              'imagePermitted': counts.get('imagePermitted', sum(bool(i.get('image')) for i in items)),
              'rejectedEntries': min(500, state.get('heldCount', 0)),
              'rejectionReasons': reason_counts(state.get('heldReasons')),
              'optionalFieldReasons': reason_counts(state.get('optionalFieldReasons')),
              'newestPublicationAt': newest,
              'countedAt': state.get('lastParsedAt', state.get('lastSuccessAt'))}
    for key in COUNTS:
        result[key] = min(500, max(0, result[key]))
    return result


def export_diagnostics(config, bundle, now=None):
    """Read an existing atomic generation. Never perform ingestion or media fetches."""
    from .media import image_key, media_response
    from .provider import is_unexpired, item_current
    now = now or datetime.now(timezone.utc)
    bundle = bundle or {}
    snapshot = bundle.get('snapshot', {})
    revoked_sources = set(snapshot.get('revokedSourceIds', []))
    revoked_items = set(snapshot.get('revokedItemIds', []))
    current = [i for i in snapshot.get('items', []) if is_unexpired(i, now) and item_current(i, now)
               and i['sourceId'] not in revoked_sources and i['id'] not in revoked_items]
    rows = []
    for source in config['sources'][:256]:
        state = bundle.get('states', {}).get(source['id'], {})
        diag = state.get('diagnostics') or source_diagnostics(source, state, now, 'not-yet-checked', False, False)
        # Explicit allowlist: arbitrary old state keys never enter diagnostics.
        clean = {key: diag.get(key) for key in source_diagnostics(source, {}, now, 'not-yet-checked', False, False)}
        items = [i for i in current if i['sourceId'] == source['id'] and source.get('enabled')
                 and source['rights'].get('titles')]
        loaded = {i['id'] for i in items if i.get('image') and media_response(bundle, image_key(i['image']), now)}
        syndicated = source.get('displayMode') == 'sponsored-syndication'
        rows.append(dict(clean, sourceId=source['id'], sourceName=source['name'],
                         publisherId=source.get('publisherId', source['id']), topics=source['topics'],
                         editorial=not syndicated, imageLoaded=len(loaded),
                         serverEligible=len(items), imageCards=len(loaded),
                         textFallbacks=len(items) - len(loaded) if not syndicated else 0,
                         completeArticlePendingImage=len(items) - len(loaded) if syndicated else 0))
    categories = []
    for topic in TOPICS:
        relevant = [r for r in rows if topic == 'headlines' or topic in r['topics']]
        items = [i for i in current if (topic == 'headlines' or topic in i.get('topics', []))
                 and any(r['sourceId'] == i['sourceId'] and r['enabled'] and r['editorial'] for r in relevant)]
        loaded = [i for i in items if i.get('image') and media_response(bundle, image_key(i['image']), now)]
        # Shared content is not user visibility. Local filters/private sessions
        # are measured only by the app, never reconstructed on this server.
        categories.append({'category': topic,
            'configured': len(relevant), 'enabled': sum(bool(r['enabled']) for r in relevant),
            'enabledEditorialPublishers': len({r['publisherId'] for r in relevant if r['enabled'] and r['editorial']}),
            **{key: sum(int(r.get(key) or 0) for r in relevant) for key in
               ('due', 'deferred', 'requested', 'fetched', *COUNTS)},
            'serverEligible': len(items), 'imageLoaded': len(loaded),
            'imageCards': len(loaded), 'textFallbacks': len(items) - len(loaded),
            'editorialWithin72Hours': sum(bool(date_value(i.get('publishedAt')) and
                now - timedelta(hours=72) <= date_value(i['publishedAt']) <= now) for i in items),
            'newestPublicationAt': max((i['publishedAt'] for i in items if date_value(i.get('publishedAt'))), default=None),
            'visibility': 'not-measured-on-server',
            'reviewStatus': config.get('reviewStatusByTopic', {}).get(topic)})
    asset = (json.dumps(registry(config), indent=2) + '\n').encode()
    return {'schemaVersion': 1, 'checkedAt': iso(now), 'providerMode': 'common-snapshot',
            'snapshotId': snapshot.get('snapshotId'), 'snapshotGeneratedAt': snapshot.get('generatedAt'),
            'snapshotExpiresAt': snapshot.get('expiresAt'), 'registryDigest': hashlib.sha256(asset).hexdigest(),
            'registryDigestEncoding': 'generated-asset-utf8', 'sources': rows, 'categories': categories,
            'readerData': 'none', 'networkRequests': 0}
