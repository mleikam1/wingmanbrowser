"""Read-only common snapshot HTTP service. No ingestion route or URL fetching."""
import hashlib
import http.client
import threading
import time
from datetime import datetime, timezone
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from .normalize import date_value
from .provider import is_unexpired
from .store import encode


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

    def read(self):
        with self.lock:
            if time.monotonic() - self.checked >= self.ttl or self.cached is None:
                # Failure preserves a prior good generation with original dates.
                try:
                    bundle = self.store.read()
                    if bundle:
                        self.cached = bundle["snapshot"]
                except Exception:
                    if self.cached is None:
                        raise
                self.checked = time.monotonic()
            return self.cached


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
            if self.path == "/healthz":
                self.reply(200, b'{"status":"ok"}')
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
            snapshot = dict(snapshot, items=[item for item in snapshot["items"] if is_unexpired(item, now)])
            data = encode(snapshot)
            etag = '"' + hashlib.sha256(data).hexdigest() + '"'
            generated = date_value(snapshot.get("generatedAt"))
            modified = format_datetime(generated, usegmt=True) if generated else None
            expires = date_value(snapshot.get("expiresAt"))
            cache = "public, max-age=60, must-revalidate" if expires and expires > datetime.now(timezone.utc) else "no-cache"
            headers = {"ETag": etag, "Cache-Control": cache}
            if modified:
                headers["Last-Modified"] = modified
            none_match = self.headers.get("If-None-Match")
            same = none_match == etag or (none_match is None and self.headers.get("If-Modified-Since") == modified)
            self.reply(304 if same else 200, b"" if same else data, headers)

        def do_POST(self):
            self.reply(405, b'{"error":"read-only"}', {"Allow": "GET"})

        def do_OPTIONS(self):
            if self.path != "/v1/snapshot.json":
                self.reply(404, b'{"error":"not-found"}')
                return
            self.reply(204, b"", {"Access-Control-Allow-Methods": "GET, OPTIONS",
                                  "Access-Control-Allow-Headers": "If-None-Match, If-Modified-Since, Accept",
                                  "Access-Control-Max-Age": "600"})

        def reply(self, status, body, headers=None):
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Expose-Headers", "ETag, Last-Modified, Retry-After")
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
