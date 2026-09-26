"""Dedicated query service, separate from read-only content and operator routes.

The stdlib runner is loopback development only. A public deployment needs an
approved authenticated operational plane, shared ledger and logging review.
"""
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
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
    def __init__(self, provider=None, metrics=None):
        self.provider, self.metrics = provider, metrics or AggregateMetrics()
        self.slots = threading.BoundedSemaphore(8)

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
            self.metrics.add('completed')
            return dto
        except BudgetError:
            self.metrics.add('failed')
            raise SearchError('budget-exhausted', 503) from None
        except SearchError:
            self.metrics.add('failed')
            raise
        except Exception:
            self.metrics.add('failed')
            raise SearchError('service-unavailable', 503) from None

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
        def reply(self, status, value):
            body = json.dumps(value, separators=(',', ':'), ensure_ascii=True).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
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
            if self.headers.get('Host') not in (f'127.0.0.1:{port}', f'localhost:{port}', f'[::1]:{port}'):
                raise SearchError('invalid-host', 403)
            origin = self.headers.get('Origin')
            if origin and origin not in allowed_origins:
                raise SearchError('origin-not-allowed', 403)
            if not guard.allow(self.client_address[0]):
                raise SearchError('service-busy', 429)
        def do_OPTIONS(self):
            try:
                self.boundary()
                if self.path != '/v1/search':
                    raise SearchError('not-found', 404)
                self.reply(200, {'status': 'ok'})
            except SearchError as exc:
                self.reply(exc.http_status, {'status': 'error', 'error': {'code': exc.code}})
        def do_GET(self):
            try:
                self.boundary()
                if self.path != '/healthz':
                    raise SearchError('not-found', 404)
                self.reply(200, {'status': 'ok', 'service': 'Wingman Search', 'localOnly': True})
            except SearchError as exc:
                self.reply(exc.http_status, {'status': 'error', 'error': {'code': exc.code}})
        do_HEAD = do_GET
        def do_POST(self):
            try:
                self.boundary()
                if self.path != '/v1/search':
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
                self.reply(200, app.search(raw))
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
