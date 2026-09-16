"""Read-only common snapshot HTTP service. No ingestion route or URL fetching."""
import hashlib
import http.client
import threading
import time
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from .normalize import date_value, iso
from .provider import is_unexpired, item_current
from .store import encode
from .media import media_response


class HeaderBudget:
    def __init__(self, stream):
        self.stream = stream
        self.remaining = 32768

    def readline(self, size=-1):
        line = self.stream.readline(min(size if size >= 0 else 32769, self.remaining + 1))
        self.remaining -= len(line)
        if self.remaining < 0:
            raise http.client.LineTooLong("request headers")
        return line


class SnapshotReader:
    def __init__(self, store, ttl=15):
        self.store, self.ttl = store, ttl
        self.cached, self.checked = None, 0
        self.lock = threading.Lock()

    def bundle(self):
        with self.lock:
            if time.monotonic() - self.checked >= self.ttl or self.cached is None:
                # Failure preserves a prior good generation with original dates.
                try:
                    bundle = self.store.read()
                    if bundle:
                        self.cached = bundle
                except Exception:
                    if self.cached is None:
                        raise
                self.checked = time.monotonic()
            return self.cached

    def read(self):
        bundle = self.bundle()
        return bundle['snapshot'] if bundle else None


def handler_for(store):
    reader = SnapshotReader(store)

    class Handler(BaseHTTPRequestHandler):
        server_version = "WingmanContent/1.0"
        sys_version = ""

        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *_args):
            # No access logs, IPs, referrers, user agents or query logging here.
            pass

        def parse_request(self):
            original = self.rfile
            self.rfile = HeaderBudget(original)
            try:
                return super().parse_request()
            finally:
                self.rfile = original

        def do_GET(self):
            if self.path in ("/healthz", "/readyz"):
                now = datetime.now(timezone.utc)
                try:
                    snapshot = reader.read()
                except Exception:
                    snapshot = None
                expiry = date_value((snapshot or {}).get('expiresAt'))
                fresh = bool(expiry and expiry > now)
                body = {'status': 'ok', 'service': 'read-only', 'checkedAt': iso(now),
                        'snapshot': 'fresh' if fresh else 'cached' if snapshot else 'unavailable',
                        'snapshotGeneratedAt': (snapshot or {}).get('generatedAt'),
                        'snapshotExpiresAt': (snapshot or {}).get('expiresAt')}
                # Liveness is separate from supply readiness. A running process
                # cannot report a missing/stale snapshot as fresh ingestion.
                self.reply(200 if self.path == '/healthz' or fresh else 503,
                           encode(body), {'Cache-Control': 'no-store'})
                return
            if self.path.startswith('/v1/media/'):
                try:
                    result = media_response(reader.bundle() or {}, self.path[len('/v1/media/'):], datetime.now(timezone.utc))
                except Exception:
                    result = None
                if result is None:
                    self.reply(404, b'{"error":"media-unavailable"}', {'Cache-Control': 'no-store'})
                else:
                    body, mime, ttl = result
                    self.reply(200, body, {'Cache-Control': 'public, max-age=%d, must-revalidate' % ttl}, content_type=mime)
                return
            if self.path != "/v1/snapshot.json":
                self.reply(404, b'{"error":"not-found"}')
                return
            try:
                snapshot = reader.read()
            except Exception:
                snapshot = None
            if snapshot is None:
                self.reply(503, b'{"error":"snapshot-unavailable"}')
                return
            now = datetime.now(timezone.utc)
            original_items = snapshot['items']
            snapshot = dict(snapshot, items=[item for item in original_items if is_unexpired(item, now) and item_current(item, now)],
                            sources=[{key: value for key, value in source.items() if key != 'diagnostics'}
                                     for source in snapshot.get('sources', [])])
            data = encode(snapshot)
            etag = '"' + hashlib.sha256(data).hexdigest() + '"'
            generated = date_value(snapshot.get("generatedAt"))
            modified = format_datetime(generated, usegmt=True) if generated else None
            expires = date_value(snapshot.get("expiresAt"))
            deadlines = [value for value in [expires] + [date_value(item.get('expiresAt'))
                         for item in snapshot['items']] if value is not None]
            for item in snapshot['items']:
                published = date_value(item.get('publishedAt'))
                if published:
                    deadlines.append(published + timedelta(days=30))
                if item.get('providerId') == 'currents':
                    fetched = date_value(item.get('fetchedAt'))
                    if fetched:
                        deadlines.append(fetched + timedelta(hours=24))
            ttl = max(0, min([60] + [int((value - now).total_seconds()) for value in deadlines])) if deadlines else 0
            cache = "public, max-age=%d, must-revalidate" % ttl if ttl else "no-cache, must-revalidate"
            headers = {"ETag": etag, "Cache-Control": cache}
            if modified:
                headers["Last-Modified"] = modified
            none_match = self.headers.get("If-None-Match")
            matches = [value.strip().removeprefix('W/') for value in (none_match or '').split(',')]
            # Expiry can change this representation without changing the saved
            # generation's date. Only ETag may validate that filtered response.
            same = etag in matches or '*' in matches or (none_match is None and modified is not None
                    and len(original_items) == len(snapshot['items'])
                    and self.headers.get("If-Modified-Since") == modified)
            self.reply(304 if same else 200, b"" if same else data, headers)

        def do_POST(self):
            self.reply(405, b'{"error":"read-only"}', {"Allow": "GET"})

        def do_OPTIONS(self):
            if self.path != "/v1/snapshot.json" and not self.path.startswith('/v1/media/'):
                self.reply(404, b'{"error":"not-found"}')
                return
            self.reply(204, b"", {"Access-Control-Allow-Methods": "GET, OPTIONS",
                                  "Access-Control-Allow-Headers": "If-None-Match, If-Modified-Since, Accept",
                                  "Access-Control-Max-Age": "600"})

        def reply(self, status, body, headers=None, content_type='application/json; charset=utf-8'):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Expose-Headers", "ETag, Last-Modified, Retry-After, Cache-Control, Content-Type")
            self.send_header("Referrer-Policy", "no-referrer")
            for key, value in (headers or {}).items():
                self.send_header(key, value)
            self.end_headers()
            if body:
                self.wfile.write(body)

    return Handler


class BoundedServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(32)
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


def serve(store, host="127.0.0.1", port=8891):
    BoundedServer((host, port), handler_for(store)).serve_forever()
