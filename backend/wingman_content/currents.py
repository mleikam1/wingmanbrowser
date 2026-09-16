"""Fixed editorial Currents ingestion; never called by the public read service.

The only authenticated HTTP call is inside BudgetGateway after a durable lease
and reservation. News requests are deliberately limited to 16 reviewed category
queries and three fixed, locally relevance-filtered supplements.
"""
import copy
import http.client
import json
import os
import re
import socket
import threading
import time
from dataclasses import dataclass
from datetime import timedelta
from urllib.parse import urlencode

from .currents_budget import (BudgetError, LocalLedger, GCSLedger, utcnow, moment,
                             stamp, tomorrow, HARD_CAP)
from .fetch import (FetchError, FetchResult, PinnedHTTPSConnection, resolve_public,
                    public_ip, inflate_chunks)
from .normalize import date_value, iso
from .provider import NewsProvider

CATEGORIES = ('general', 'sport', 'arts_culture_entertainment', 'science_technology',
              'economy_business_finance', 'society', 'politics_government',
              'lifestyle_leisure', 'human_interest', 'crime_law_justice', 'education',
              'environment', 'labour', 'health', 'automotive', 'real_estate')
FAST_CATEGORIES = frozenset(CATEGORIES[:5])
CATEGORY_TOPICS = dict(zip(CATEGORIES, ('headlines', 'sports', 'entertainment',
    'science_technology', 'business', 'society', 'politics_government',
    'lifestyle_leisure', 'human_interest', 'crime_law_justice', 'education',
    'environment', 'labour', 'health', 'automotive', 'real_estate')))
DERIVED_QUERIES = {'food': '(recipes OR cooking OR restaurants)',
                   'fashion': '(clothing OR "fashion design" OR runway)',
                   'travel': '(travel OR tourism OR destinations)'}
API_HOST = 'api.currentsapi.services'
METADATA_SECONDS = 7 * 86400
NORMAL_RUN_MAX = 4


def interval(category):
    return 7200 if category in FAST_CATEGORIES else 21600


def phase(category):
    index = CATEGORIES.index(category)
    return (0, 0, 1800, 3600, 5400)[index] if index < 5 else (index - 5) * 1800


def next_slot(now, every, offset=0, inclusive=False):
    """UTC cadence, skipping missed periods rather than making catch-up calls."""
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    elapsed = (now - midnight).total_seconds() - offset
    ordinal = int(elapsed // every)
    candidate = midnight + timedelta(seconds=offset + ordinal * every)
    if candidate < now or (candidate == now and not inclusive):
        candidate += timedelta(seconds=every)
    return candidate


def _validate_request(path, params, now):
    if not isinstance(params, dict):
        raise BudgetError('invalid-request')
    if path == '/v1/auth' or path in ('/v2/available/categories', '/v2/available/regions', '/v2/available/languages'):
        if params:
            raise BudgetError('invalid-request')
        return
    base = {'language': 'en', 'country': 'US', 'page_number': 1, 'page_size': 20}
    if path == '/v2/latest-news':
        if set(params) != set(base) | {'category'} or params.get('category') not in CATEGORIES:
            raise BudgetError('invalid-request')
    elif path == '/v2/search':
        if (set(params) != set(base) | {'query', 'start_date', 'end_date'} or
                params.get('query') not in DERIVED_QUERIES.values()):
            raise BudgetError('invalid-request')
        if (params['start_date'] != stamp(now - timedelta(days=7)) or params['end_date'] != stamp(now)):
            raise BudgetError('invalid-search-window')
    else:
        raise BudgetError('unapproved-endpoint')
    if any(params.get(key) != value for key, value in base.items()):
        raise BudgetError('invalid-request')


class _CurrentsTransport:
    """HTTPS, pinned public address, no redirects/retries, bounded bytes/time."""
    def __init__(self, resolver=resolve_public, connector=PinnedHTTPSConnection):
        self.resolver, self.connector = resolver, connector

    def request(self, path, params, authorization):
        deadline = time.monotonic() + 25
        connection = None
        timer = None
        response_status = None
        headers = {}
        try:
            addresses = self.resolver(API_HOST, 4)
            if not addresses or any(not public_ip(value) for value in addresses):
                raise FetchError('non-public-dns')
            connection = self.connector(API_HOST, addresses[0], min(8, max(.01, deadline - time.monotonic())))
            def interrupt():
                sock = connection.sock
                if sock:
                    try:
                        sock.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    sock.close()
            timer = threading.Timer(max(.001, deadline - time.monotonic()), interrupt)
            timer.daemon = True
            timer.start()
            target = path + ('?' + urlencode(params) if params else '')
            connection.request('GET', target, headers={
                'Authorization': authorization, 'Accept': 'application/json',
                'Accept-Encoding': 'gzip', 'Connection': 'close',
                'User-Agent': 'WingmanSharedContent/1.0'})
            response = connection.getresponse()
            pairs = response.getheaders()
            if sum(len(k) + len(v) for k, v in pairs) > 32768:
                raise FetchError('header-size-limit')
            headers = {}
            for name, value in pairs:
                name = name.lower()
                if name in headers and name not in ('cache-control', 'vary'):
                    raise FetchError('duplicate-response-metadata')
                headers[name] = headers.get(name, '') + (', ' if name in headers else '') + value
            response_status = response.status
            # Return errors without following Location or echoing untrusted bodies.
            if response.status != 200:
                return FetchResult(response.status, headers, b'')
            length = headers.get('content-length', '')
            if length and (not length.isdigit() or len(length) > 9 or int(length) > 1024 * 1024):
                return FetchResult(200, headers, b'')
            if headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json':
                return FetchResult(200, headers, b'')
            body = inflate_chunks(iter(lambda: response.read(16384), b''),
                                  headers.get('content-encoding', 'identity').lower(), deadline)
            return FetchResult(200, headers, body)
        except Exception:
            if response_status is not None:
                # Quota headers still count when a response body is truncated,
                # malformed, over-size, or times out during the bounded read.
                return FetchResult(response_status, headers, b'')
            # Suppress nested exception strings that may include request headers.
            raise FetchError('currents-transport-error') from None
        finally:
            if timer:
                timer.cancel()
            if connection:
                connection.close()


@dataclass
class ApiResult:
    data: dict
    headers: dict
    status: int
    job: dict


class BudgetGateway:
    def __init__(self, ledger, key=None, transport=None, spacing_seconds=3, sleeper=time.sleep):
        self.ledger = ledger
        self._key = key if key is not None else os.environ.get('CURRENTS_API_KEY')
        self._transport = transport or _CurrentsTransport()
        self.spacing_seconds = max(0, spacing_seconds)
        self.sleeper = sleeper
        self.before_request = None

    @property
    def configured(self):
        return (isinstance(self._key, str) and bool(self._key) and len(self._key) <= 4096
                and not any(ord(c) < 33 or ord(c) == 127 for c in self._key))

    def request(self, path, params, job_id, now, *, next_due, supplement=False, allow_auth=False):
        _validate_request(path, params, now)
        if allow_auth and path != '/v1/auth':
            raise BudgetError('invalid-request')
        if (path == '/v2/search') != supplement:
            raise BudgetError('invalid-request')
        if not self.configured:
            raise BudgetError('currents-unconfigured')
        if self.before_request:
            self.before_request()
        started = time.monotonic()
        reservation = self.ledger.reserve(job_id, path, params, now, next_due=next_due,
            supplement=supplement, allow_auth=allow_auth, spacing_seconds=self.spacing_seconds)
        try:
            return self._reserved_request(path, params, now, reservation, started)
        except BudgetError as exc:
            raise BudgetError(exc.reason, attempted=True) from None

    def _reserved_request(self, path, params, now, reservation, started):
        # No transport occurs in a storage transaction/CAS retry callback.
        self.ledger.assert_lease(reservation, now + timedelta(seconds=time.monotonic() - started))
        if time.monotonic() - started >= 30:
            # Enough lease must remain for the entire bounded HTTP deadline.
            raise BudgetError('lease-lost')
        if self.before_request:
            self.before_request()
        if time.monotonic() - started >= 30:
            raise BudgetError('lease-lost')
        response = None
        error = None
        data = {}
        try:
            response = self._transport.request(path, params, 'Bearer ' + self._key)
            if response.status == 200:
                try:
                    if len(response.body) > 2 * 1024 * 1024:
                        raise ValueError()
                    data = json.loads(response.body)
                    if not isinstance(data, dict) or data.get('status') != 'ok':
                        raise ValueError()
                    if path in ('/v2/search', '/v2/latest-news'):
                        if not isinstance(data.get('news'), list) or len(data['news']) > 20:
                            raise ValueError()
                except (ValueError, TypeError, UnicodeError):
                    error = 'invalid-envelope'
        except Exception:
            error = 'transport-error'
        finished = now + timedelta(seconds=time.monotonic() - started)
        job = self.ledger.finish(reservation, finished, status=response.status if response else None,
                                 headers=response.headers if response else {}, error=error)
        if error:
            raise BudgetError(error)
        if response.status != 200:
            raise BudgetError('http-%d' % response.status)
        return ApiResult(data, {k.lower(): v for k, v in response.headers.items()}, response.status, job)

    def pace(self):
        if self.spacing_seconds:
            self.sleeper(self.spacing_seconds)


def _codes(payload, name):
    values = payload.get(name)
    if isinstance(values, dict):
        candidates = list(values) + [v for v in values.values() if isinstance(v, str)]
    elif isinstance(values, list):
        candidates = []
        for value in values:
            if isinstance(value, str):
                candidates.append(value)
            elif isinstance(value, dict):
                candidates.extend(value[key] for key in ('id', 'code', 'name') if isinstance(value.get(key), str))
    else:
        raise BudgetError('invalid-metadata')
    if len(candidates) > 1000 or not candidates or any(len(v) > 100 for v in candidates):
        raise BudgetError('invalid-metadata')
    return sorted(set(candidates))


class CurrentsProvider(NewsProvider):
    def __init__(self, destination_policy, gateway):
        self.destination_policy, self.gateway = destination_policy, gateway

    def _refresh_metadata(self, name, current):
        result = self.gateway.request('/v2/available/' + name, {}, 'metadata:' + name,
            current, next_due=current + timedelta(days=1))
        values = _codes(result.data, name)
        if name == 'categories' and not (set(values) & set(CATEGORIES)):
            raise BudgetError('invalid-metadata')
        if name == 'regions' and 'US' not in values:
            raise BudgetError('metadata-missing-us')
        if name == 'languages' and 'en' not in values:
            raise BudgetError('metadata-missing-en')
        def cache(state):
            state['metadata'][name] = {'values': values, 'fetchedAt': stamp(current),
                'expiresAt': stamp(current + timedelta(seconds=METADATA_SECONDS))}
            state['jobs']['metadata:' + name]['nextDue'] = stamp(current + timedelta(seconds=METADATA_SECONDS))
        self.gateway.ledger.update(cache)
        return {'operation': name, 'status': 'ok', 'count': len(values),
                'reviewRequired': sorted(set(values) - set(CATEGORIES)) if name == 'categories' else []}

    def setup(self, now=None, replace_credential=False):
        """One deliberate credential check; cached metadata refresh uses same cap."""
        live = now is None
        now = now or utcnow()
        started = time.monotonic()
        if not self.gateway.configured:
            raise BudgetError('currents-unconfigured')
        def begin(state):
            if replace_credential:
                state['credentialRevision'] += 1
                state.update(authAttempted=False, authStatus=None, pauseReason=None, pauseUntil=None)
            return copy.deepcopy(state)
        state = self.gateway.ledger.update(begin)
        report = []
        if not state['authAttempted']:
            revision = state['credentialRevision']
            try:
                self.gateway.request('/v1/auth', {}, 'setup:auth:%d' % revision, now,
                                     next_due=now + timedelta(days=366), allow_auth=True)
                def authenticated(s):
                    if s['credentialRevision'] == revision:
                        s.update(authStatus='ok', pauseReason=None)
                self.gateway.ledger.update(authenticated)
                report.append({'operation': 'auth', 'status': 'ok'})
            except BudgetError as exc:
                if exc.attempted:
                    def failed(s):
                        if s['credentialRevision'] == revision:
                            s.update(authStatus='failed', pauseReason='authentication')
                    self.gateway.ledger.update(failed)
                report.append({'operation': 'auth', 'status': exc.reason})
                return report
            self.gateway.pace()
        elif state['authStatus'] != 'ok':
            return [{'operation': 'auth', 'status': 'operator-correction-required'}]
        for name in ('categories', 'regions', 'languages'):
            current = utcnow() if live else now + timedelta(seconds=time.monotonic() - started)
            state = self.gateway.ledger.diagnostics(current)
            cached = state['metadata'].get(name)
            if cached and moment(cached['expiresAt']) > current:
                report.append({'operation': name, 'status': 'cached'})
                continue
            try:
                report.append(self._refresh_metadata(name, current))
            except BudgetError as exc:
                report.append({'operation': name, 'status': exc.reason, 'lastKnownRetained': bool(cached)})
                if exc.reason in ('http-401', 'http-403', 'http-429', 'ledger-unavailable', 'ledger-corrupt'):
                    break
            self.gateway.pace()
        return report

    def _initialize_jobs(self, now):
        def jobs(state):
            for category in CATEGORIES:
                state['jobs'].setdefault('latest:' + category, {
                    'nextDue': stamp(next_slot(now, interval(category), phase(category), inclusive=True)), 'failures': 0})
            for index, topic in enumerate(DERIVED_QUERIES):
                state['jobs'].setdefault('supplement:' + topic, {
                    'nextDue': stamp(next_slot(now, 21600, 19800 + index * 1800, inclusive=True)), 'failures': 0})
        self.gateway.ledger.update(jobs)

    def _run(self, source, prior, now=None, *, bootstrap=False):
        live = now is None
        now = now or utcnow()
        started = time.monotonic()
        state = copy.deepcopy(prior)
        pools = {key: [item for item in values if (date_value(item.get('expiresAt')) or now) > now]
                 for key, values in prior.get('currentsPools', {}).items()}
        state['currentsPools'] = pools
        state['items'] = [item for item in prior.get('items', []) if (date_value(item.get('expiresAt')) or now) > now]
        if not pools and state['items']:
            # Recover eligible cache representations from an earlier schema.
            pools['prior-cache'] = copy.deepcopy(state['items'])
        reports = []
        state['lastHttpStatus'] = None
        state['nextRefreshAt'] = stamp(next_slot(now, 1800))
        if not self.gateway.configured:
            state.update(error='currents-unconfigured', status='configuration')
            return state
        try:
            self._initialize_jobs(now)
            ledger = self.gateway.ledger.diagnostics(now)
            metadata = ledger['metadata']
            if not all(name in metadata for name in ('categories', 'regions', 'languages')) or ledger['authStatus'] != 'ok':
                state.update(error='currents-setup-required', status='configuration')
                return state
            metadata_attempts = 0
            if not bootstrap:
                # A weekly administrative refresh shares the same four-attempt
                # tick ceiling. Last validated codes remain usable on failure.
                for name in ('categories', 'regions', 'languages'):
                    if moment(metadata[name]['expiresAt']) > now:
                        continue
                    job = ledger['jobs'].get('metadata:' + name)
                    if job and (job.get('held') or moment(job['nextDue']) > now):
                        continue
                    current = utcnow() if live else now + timedelta(seconds=time.monotonic() - started)
                    metadata_attempts += 1
                    try:
                        reports.append(self._refresh_metadata(name, current))
                    except BudgetError as exc:
                        reports.append({'operation': name, 'status': exc.reason, 'lastKnownRetained': True})
                        if exc.reason in ('http-401', 'http-403', 'http-429', 'ledger-unavailable', 'ledger-corrupt'):
                            raise
                    self.gateway.pace()
                ledger = self.gateway.ledger.diagnostics(now)
                metadata = ledger['metadata']
            allowed = set(metadata['categories']['values']) & set(CATEGORIES)
            candidates = []
            for category in CATEGORIES:
                job_id = 'latest:' + category
                job = ledger['jobs'][job_id]
                if category in allowed and not job.get('held') and (bootstrap or moment(job['nextDue']) <= now):
                    candidates.append((job['nextDue'], job_id, category))
            if not bootstrap:
                for topic in DERIVED_QUERIES:
                    job_id = 'supplement:' + topic
                    job = ledger['jobs'][job_id]
                    # Count unique current items across all already fetched pools.
                    count = len({item['id'] for values in pools.values() for item in values
                                 if topic in item.get('topics', [])})
                    if not job.get('held') and count < 5 and moment(job['nextDue']) <= now:
                        candidates.append((job['nextDue'], job_id, topic))
                    elif count >= 5 and moment(job['nextDue']) <= now:
                        self.gateway.ledger.update(lambda s, k=job_id: s['jobs'][k].update(
                            nextDue=stamp(next_slot(now, 21600)), status='sufficient-local-pool'))
            candidates.sort(key=lambda value: (value[0], value[1]))
            if bootstrap:
                # One operator pass sets due times through normal reservation.
                # Previously attempted slots are never repeated on restart.
                candidates = [row for row in candidates if not ledger['jobs'][row[1]].get('lastAttemptAt')]
            for _, job_id, category in candidates[:16 if bootstrap else NORMAL_RUN_MAX - metadata_attempts]:
                current = utcnow() if live else now + timedelta(seconds=time.monotonic() - started)
                supplement = job_id.startswith('supplement:')
                params = {'language': 'en', 'country': 'US', 'page_number': 1, 'page_size': 20}
                if supplement:
                    params.update(query=DERIVED_QUERIES[category], start_date=stamp(current - timedelta(days=7)), end_date=stamp(current))
                else:
                    params['category'] = category
                if bootstrap:
                    # Only untouched jobs are moved forward for this paced fill.
                    def bootstrap_due(s):
                        job = s['jobs'][job_id]
                        if not job.get('lastAttemptAt'):
                            job['nextDue'] = stamp(current)
                    self.gateway.ledger.update(bootstrap_due)
                try:
                    every = 21600 if supplement else interval(category)
                    next_due = (current + timedelta(seconds=every) if supplement or bootstrap else
                                next_slot(current, every, phase(category)))
                    result = self.gateway.request('/v2/search' if supplement else '/v2/latest-news', params,
                        job_id, current, next_due=next_due, supplement=supplement)
                    from .normalize import parse_currents_news
                    items, held = parse_currents_news(result.data['news'], source, current,
                        self.destination_policy, provider_category=None if supplement else category)
                    if supplement:
                        items = [item for item in items if category in item.get('topics', [])]
                    cache_control = result.headers.get('cache-control', '').lower()
                    prohibited = any(part.strip().split('=')[0] in ('no-store', 'private', 'no-cache') for part in cache_control.split(','))
                    prohibited = prohibited or 'no-cache' in result.headers.get('pragma', '').lower()
                    if prohibited:
                        items = []
                    maxima = re.findall(r'(?:^|,)\s*(?:s-maxage|max-age)\s*=\s*"?(\d+)', cache_control)
                    if maxima:
                        age = result.headers.get('age', '0')
                        seconds = max(0, min(int(value[:10]) for value in maxima) -
                                      (int(age[:10]) if age.isdigit() else 0))
                        for item in items:
                            item['expiresAt'] = stamp(min(moment(item['expiresAt']), current + timedelta(seconds=seconds)))
                    expires = date_value(result.headers.get('expires'))
                    if expires:
                        for item in items:
                            item['expiresAt'] = stamp(min(moment(item['expiresAt']), expires))
                    # Never retain a raw response or full body in state or ledger.
                    pools[job_id] = items
                    state.update(lastSuccessAt=stamp(current), fetchedAt=stamp(current), lastHttpStatus=200,
                                 error=None, failures=0, status='fresh' if items else 'valid-empty')
                    reports.append({'category': category, 'operation': 'search' if supplement else 'latest-news',
                        'status': 'cache-prohibited' if prohibited else 'ok' if items else 'valid-empty',
                        'returned': len(result.data['news']), 'permitted': len(items),
                        'imageCards': sum(bool(item.get('image')) for item in items), 'held': held})
                except BudgetError as exc:
                    reports.append({'category': category, 'status': exc.reason, 'returned': 0, 'permitted': 0, 'imageCards': 0})
                    if exc.reason not in ('not-due', 'query-held'):
                        state['error'] = exc.reason
                    if exc.reason in ('http-401', 'http-403', 'http-429', 'authentication-paused',
                            'provider-wait', 'local-budget-exhausted', 'provider-quota-reserve',
                            'lease-busy', 'spacing-wait', 'ledger-corrupt', 'ledger-unavailable', 'lease-lost'):
                        break
                self.gateway.pace()
        except BudgetError as exc:
            state['error'] = exc.reason
        merged = {}
        for values in pools.values():
            for item in values:
                old = merged.get(item['id'])
                if old:
                    # Same provider/right representation only; publication date is unchanged.
                    topics = sorted(set(old['topics']) | set(item['topics']))
                    categories = sorted(set(old.get('providerCategories', [])) | set(item.get('providerCategories', [])))
                    if (item.get('fetchedAt') or '') > (old.get('fetchedAt') or ''):
                        old = merged[item['id']] = copy.deepcopy(item)
                    old['topics'], old['providerCategories'] = topics, categories
                else:
                    merged[item['id']] = copy.deepcopy(item)
        state.update(items=list(merged.values()), currentsPools=pools, jobReport=reports,
                     refreshSuspended=False, normalizationVersion=1)
        if state['items'] and state.get('status') == 'valid-empty':
            state['status'] = 'fresh'
        if state.get('error'):
            state['status'] = 'cached' if state.get('lastSuccessAt') else 'unavailable'
        return state

    def refresh(self, source, prior, now):
        return self._run(source, prior, now)

    def bootstrap(self, source, prior, now=None):
        return self._run(source, prior, now, bootstrap=True)
