"""Dedicated query service, separate from read-only content and operator routes.

The stdlib runner is loopback development only. A public deployment needs an
approved authenticated operational plane, shared ledger and logging review.
"""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import threading
import time
from urllib.parse import urlsplit
from wingman_content.server import HeaderBudget
from .budget import BudgetError
from .contracts import SearchRequest, SearchError, decode_json

class AggregateMetrics:
    """Fixture/local aggregate counters. No query, address, token or consumer key.

    Kept separate from the durable provider-spending ledger. Restarts can lose
    these development metrics; never represent them as verified live revenue.
    """
    def __init__(self):
        self._lock, self._counts = threading.Lock(), Counter()
    def add(self, name):
        if name not in ('submitted', 'completed', 'failed', 'web', 'news'):
            raise ValueError('unreviewed-counter')
        with self._lock:
            self._counts[name] += 1
    def snapshot(self):
        with self._lock:
            return dict(self._counts, scope='local-process', durable=False)

class BurstGuard:
    """Aggregate loopback development rate cap; no peer identifiers retained."""
    def __init__(self, limit=20, clock=time.monotonic):
        self._lock = threading.Lock()
        self.limit, self.clock = limit, clock
        self._start, self._count = clock(), 0
    def allow(self, address):
        now = self.clock()
        with self._lock:
            if now - self._start >= 60:
                self._start, self._count = now, 0
            self._count += 1
            return self._count <= self.limit

class SearchApplication:
    def __init__(self, provider=None, metrics=None, ads=None):
        self.provider, self.metrics = provider, metrics or AggregateMetrics()
        self.ads = ads
        self.slots = threading.BoundedSemaphore(8)
        self.ad_slots = threading.BoundedSemaphore(4)
        self.outcome_metrics_degraded = False

    def outcome_metric(self, name):
        try:
            self.metrics.add(name)
        except Exception:
            # A completed paid request still returns its usable results. Keep
            # this operator-health signal separate from financial accounting;
            # never turn a reporting outage into another paid consumer retry.
            self.outcome_metrics_degraded = True

    def search(self, raw):
        self.metrics.add('submitted')
        try:
            request = SearchRequest.parse(raw)
            self.metrics.add(request.kind)
            if self.provider is None:
                raise SearchError('configuration-required', 503)
            if not self.slots.acquire(blocking=False):
                raise SearchError('service-busy', 503)
            try:
                dto, intent = self.provider.search(request)
            finally:
                self.slots.release()
            if (self.ads is not None and request.kind == 'web' and request.offset == 0
                    and request.context == 'normal' and intent and dto.get('results')):
                try:
                    grant = self.ads.issue_context(intent=intent, country=request.country,
                        language=request.search_lang, context='normal', fixture=dto.get('fixture') is True,
                        organic_count=len(dto['results']))
                    if grant:
                        dto = dict(dto, adContext=grant)
                except Exception:
                    pass  # Local context signing must never fail organic search.
            self.outcome_metric('completed')
            return dto
        except BudgetError as exc:
            self.outcome_metric('failed')
            code = ('budget-exhausted' if exc.code in ('attempt_budget_exhausted', 'shared_ledger_capacity_exhausted')
                    else 'provider-rate-limited' if exc.code in ('provider_quota_exhausted', 'shared_backoff')
                    else 'service-busy' if exc.code == 'shared_ledger_contention'
                    else 'service-unavailable')
            raise SearchError(code, 503) from None
        except SearchError:
            self.outcome_metric('failed')
            raise
        except Exception:
            self.outcome_metric('failed')
            raise SearchError('service-unavailable', 503) from None

    def ad_request(self, path, raw):
        if self.ads is None:
            if path == '/v1/ads/decision':
                return {'schemaVersion': 1, 'status': 'no-fill', 'fixture': False,
                        'noFillReason': 'configuration-required', 'ad': None}
            return {'schemaVersion': 1, 'status': 'rejected', 'fixture': False,
                    'billable': False, 'chargedMicros': 0, 'testChargedMicros': 0,
                    'landingUrl': None, 'errorCode': 'configuration-required'}
        if not self.ad_slots.acquire(blocking=False):
            raise SearchError('service-busy', 503)
        try:
            return self.ads.decision(raw) if path == '/v1/ads/decision' else self.ads.event(raw)
        except Exception:
            raise SearchError('service-unavailable', 503) from None
        finally:
            self.ad_slots.release()

    def ad_asset(self, path):
        match = re.fullmatch(r'/v1/ads/assets/([a-f0-9]{64})\.png', path)
        if not match or self.ads is None:
            raise SearchError('not-found', 404)
        try:
            body, mime = self.ads.asset(match[1])
            if mime != 'image/png' or not isinstance(body, bytes) or len(body) > 1024 * 1024:
                raise ValueError()
            return body, mime
        except Exception:
            raise SearchError('not-found', 404) from None

def valid_local_origin(value):
    try:
        p = urlsplit(value)
        return (p.scheme == 'http' and p.hostname in ('127.0.0.1', 'localhost', '::1')
                and not p.path and not p.query and not p.fragment and not p.username
                and p.port is not None and 1 <= p.port <= 65535)
    except ValueError:
        return False

def handler_for(app, origins=()):
    allowed_origins = frozenset(origins)
    if any(not valid_local_origin(origin) for origin in allowed_origins):
        raise ValueError('local-origin-required')
    guard = BurstGuard()
    ad_guard = BurstGuard(limit=120)
    class Handler(BaseHTTPRequestHandler):
        server_version = 'WingmanSearch/1.0'
        sys_version = ''
        def setup(self):
            super().setup()
            self.connection.settimeout(12)
        def log_message(self, *_):
            pass
        def parse_request(self):
            original = self.rfile
            self.rfile = HeaderBudget(original)
            try:
                return super().parse_request()
            finally:
                self.rfile = original
        def send_error(self, code, message=None, explain=None):
            self.reply(code, {'schemaVersion': 1, 'status': 'error', 'error': {'code': 'invalid-request'}})
        def reply(self, status, value, mime='application/json; charset=utf-8'):
            body = value if isinstance(value, bytes) else json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode()
            self.send_response(status)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store, private')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'")
            self.send_header('Cross-Origin-Resource-Policy', 'same-site')
            origin = self.headers.get('Origin') if hasattr(self, 'headers') else None
            if origin in allowed_origins:
                self.send_header('Access-Control-Allow-Origin', origin)
                self.send_header('Vary', 'Origin')
                self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            self.send_header('Connection', 'close')
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(body)
            self.close_connection = True
        def boundary(self):
            port = self.server.server_address[1]
            if (len(self.headers.get_all('Host') or []) != 1 or
                    self.headers.get('Host') not in (f'127.0.0.1:{port}', f'localhost:{port}', f'[::1]:{port}')):
                raise SearchError('invalid-host', 403)
            origin = self.headers.get('Origin')
            if len(self.headers.get_all('Origin') or []) > 1 or (origin and origin not in allowed_origins):
                raise SearchError('origin-not-allowed', 403)
            limiter = ad_guard if self.path.startswith('/v1/ads/') else guard
            if not limiter.allow(self.client_address[0]):
                raise SearchError('service-busy', 429)
        def do_OPTIONS(self):
            try:
                self.boundary()
                if self.path not in ('/v1/search', '/v1/ads/decision', '/v1/ads/event'):
                    raise SearchError('not-found', 404)
                self.reply(200, {'status': 'ok'})
            except SearchError as exc:
                self.reply(exc.http_status, {'status': 'error', 'error': {'code': exc.code}})
        def do_GET(self):
            try:
                self.boundary()
                if self.path.startswith('/v1/ads/assets/'):
                    body, mime = app.ad_asset(self.path)
                    self.reply(200, body, mime)
                    return
                if self.path != '/healthz':
                    raise SearchError('not-found', 404)
                self.reply(200, {'status': 'ok', 'service': 'Wingman Search', 'localOnly': True})
            except SearchError as exc:
                self.reply(exc.http_status, {'status': 'error', 'error': {'code': exc.code}})
        do_HEAD = do_GET
        def do_POST(self):
            try:
                self.boundary()
                if self.path not in ('/v1/search', '/v1/ads/decision', '/v1/ads/event'):
                    raise SearchError('not-found', 404)
                lengths = self.headers.get_all('Content-Length') or []
                if (len(lengths) != 1 or not lengths[0].isdigit() or len(lengths[0]) > 5
                        or not 2 <= int(lengths[0]) <= 8192 or self.headers.get('Transfer-Encoding')):
                    raise SearchError('request-size', 413)
                if self.headers.get_content_type() != 'application/json':
                    raise SearchError('json-required', 415)
                body = self.rfile.read(int(lengths[0]))
                if len(body) != int(lengths[0]):
                    raise SearchError('invalid-request')
                try:
                    raw = decode_json(body, 8192)
                except SearchError:
                    raise SearchError('invalid-request') from None
                self.reply(200, app.search(raw) if self.path == '/v1/search' else app.ad_request(self.path, raw))
            except SearchError as exc:
                self.reply(exc.http_status, {'schemaVersion': 1, 'status': 'error', 'error': {'code': exc.code}})
            except Exception:
                self.reply(503, {'schemaVersion': 1, 'status': 'error', 'error': {'code': 'service-unavailable'}})
    return Handler

class LocalServer(ThreadingHTTPServer):
    daemon_threads = True
    def handle_error(self, request, client_address):
        # Suppress traceback/peer output; no query-bearing default server logs.
        pass

def serve(app, *, host='127.0.0.1', port=8895, origins=()):
    if host != '127.0.0.1':
        raise ValueError('development-runner-requires-loopback')
    LocalServer((host, port), handler_for(app, origins)).serve_forever()
