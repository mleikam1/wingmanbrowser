"""Transient, single-use capabilities for explicit News result thumbnails.

Only Brave's returned thumbnail CDN URLs enter this process-local registry.
No provider credential, query text, caller identity, image bytes, or image URL
is written to disk. Fetch consumes and removes its URL before network I/O.
"""
from __future__ import annotations

from dataclasses import dataclass
from collections import Counter
from datetime import datetime, timezone
import io
import re
import secrets
import socket
import threading
import time
from urllib.parse import unquote, urlsplit
import warnings

from PIL import Image
from wingman_content.fetch import PinnedHTTPSConnection, public_ip, resolve_public
from .contracts import SearchError

CDN_HOST = 'imgs.search.brave.com'
FIXTURE_SOURCE = 'https://' + CDN_HOST + '/wingman-synthetic-thumbnail.png'
MAX_WIRE_BYTES = 1024 * 1024
MAX_PNG_BYTES = 128 * 1024
MAX_TOKENS = 128
TOKEN_TTL_SECONDS = 300
TOKEN_PATTERN = re.compile(r'[a-f0-9]{64}')
RASTER_TYPES = {'image/jpeg': 'JPEG', 'image/png': 'PNG', 'image/webp': 'WEBP'}
THUMBNAIL_PATH = '/v1/search/thumbnail'
RELEASE_PATH = '/v1/search/thumbnails/release'
THUMBNAIL_PATHS = (THUMBNAIL_PATH, RELEASE_PATH)


def checked_thumbnail_url(value):
    if (not isinstance(value, str) or not 1 <= len(value) <= 4096
            or not value.isascii() or re.search(r'[\x00-\x20\x7f\\]', value)):
        return None
    try:
        url = urlsplit(value)
        decoded = unquote(unquote(url.path))
        decoded_query = unquote(unquote(url.query))
        if (url.scheme != 'https' or url.hostname != CDN_HOST
                or url.username is not None or url.password is not None
                or url.port not in (None, 443) or '#' in value
                or not url.path.startswith('/') or decoded.startswith('//')
                or any(part in ('.', '..') for part in decoded.split('/'))
                or re.search(r'[\x00-\x20\x7f\\]', decoded + decoded_query)
                or re.search(r'%(?:00|0d|0a|2e|2f|5c|25)', decoded, re.I)):
            return None
        return value
    except (ValueError, UnicodeError):
        return None


def sanitize_png(data, mime):
    """Decode static raster pixels and create fresh RGB pixels, stripping metadata."""
    if (not isinstance(data, bytes) or not data or len(data) > MAX_WIRE_BYTES
            or mime not in RASTER_TYPES):
        raise ValueError('thumbnail-format')
    with warnings.catch_warnings():
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(data)) as decoded:
            width, height = decoded.size
            if (decoded.format != RASTER_TYPES[mime] or getattr(decoded, 'n_frames', 1) != 1
                    or min(width, height) < 16 or max(width, height) > 2048
                    or width * height > 4 * 1024 * 1024):
                raise ValueError('thumbnail-dimensions')
            decoded.verify()
        with Image.open(io.BytesIO(data)) as decoded:
            decoded.load()
            converted = decoded.convert('RGB')
            converted.thumbnail((256, 144), Image.Resampling.LANCZOS)
            # A new image discards EXIF, ICC, comments and embedded text fields.
            # Preserve extreme aspect ratios while meeting the client's minimum
            # decoded dimensions. Padding also avoids distorting narrow images.
            size = (max(16, converted.width), max(16, converted.height))
            clean = Image.new('RGB', size, (238, 241, 245))
            clean.paste(converted, ((size[0] - converted.width) // 2,
                                    (size[1] - converted.height) // 2))
            output = io.BytesIO()
            clean.save(output, format='PNG')
            result = output.getvalue()
            if not result or len(result) > MAX_PNG_BYTES:
                raise ValueError('thumbnail-output-size')
            return result


class ThumbnailTransport:
    """No redirect, retry, provider credential, cookie or referrer propagation."""
    def __init__(self, *, resolver=resolve_public, connector=PinnedHTTPSConnection):
        self.resolver, self.connector = resolver, connector

    def fetch(self, source):
        if checked_thumbnail_url(source) is None:
            raise ValueError('thumbnail-unavailable')
        connection = timer = None
        deadline = time.monotonic() + 5
        try:
            addresses = self.resolver(CDN_HOST, 2)
            if not addresses or any(not public_ip(address) for address in addresses):
                raise ValueError('thumbnail-unavailable')
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError('thumbnail-unavailable')
            connection = self.connector(CDN_HOST, addresses[0], min(3, remaining))
            def stop():
                sock = connection.sock
                if sock:
                    try:
                        sock.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    sock.close()
            timer = threading.Timer(max(.01, deadline - time.monotonic()), stop)
            timer.daemon = True
            timer.start()
            url = urlsplit(source)
            path = url.path + ('?' + url.query if url.query else '')
            connection.request('GET', path, headers={'Accept': 'image/jpeg, image/png, image/webp',
                'Accept-Encoding': 'identity', 'User-Agent': 'WingmanThumbnail/1.0', 'Connection': 'close'})
            response = connection.getresponse()
            if response.status != 200:
                raise ValueError('thumbnail-unavailable')
            pairs, headers = response.getheaders(), {}
            if sum(len(k) + len(v) for k, v in pairs) > 16384:
                raise ValueError('thumbnail-unavailable')
            for name, value in pairs:
                name = name.lower()
                if name in ('content-type', 'content-length', 'content-encoding'):
                    if name in headers:
                        raise ValueError('thumbnail-unavailable')
                    headers[name] = value
            mime = headers.get('content-type', '').split(';')[0].strip().lower()
            length = headers.get('content-length')
            if (mime not in RASTER_TYPES or headers.get('content-encoding', 'identity').lower() not in ('', 'identity')
                    or length is not None and (not length.isascii() or not length.isdecimal()
                        or len(length) > 8 or not 1 <= int(length) <= MAX_WIRE_BYTES)):
                raise ValueError('thumbnail-unavailable')
            body = bytearray()
            while time.monotonic() < deadline:
                chunk = response.read(min(16384, MAX_WIRE_BYTES + 1 - len(body)))
                if not chunk:
                    if length is not None and len(body) != int(length):
                        raise ValueError('thumbnail-unavailable')
                    return bytes(body), mime
                body.extend(chunk)
                if len(body) > MAX_WIRE_BYTES:
                    break
            raise ValueError('thumbnail-unavailable')
        except Exception:
            raise ValueError('thumbnail-unavailable') from None
        finally:
            if timer is not None:
                timer.cancel()
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass


@dataclass(repr=False)
class _Entry:
    source: str | None
    deadline: float
    expires: float
    consumed: bool = False


class ThumbnailService:
    def __init__(self, *, fixture=False, transport=None, clock=time.time,
                 monotonic=time.monotonic, timer_factory=threading.Timer):
        self.fixture = fixture
        self.transport = transport or ThumbnailTransport()
        self.clock, self.monotonic, self.timer_factory = clock, monotonic, timer_factory
        self._entries = {}
        self._lock = threading.Lock()
        self._slots = threading.BoundedSemaphore(2)
        self._timer = None
        self._closed = False
        self._counts = Counter()

    def _expire_locked(self):
        now, monotonic = self.clock(), self.monotonic()
        for token, entry in list(self._entries.items()):
            if now >= entry.expires or monotonic >= entry.deadline:
                del self._entries[token]
                self._counts['expired'] += 1

    def _schedule_locked(self):
        if self._timer is None and self._entries and not self._closed:
            delay = min(entry.deadline for entry in self._entries.values()) - self.monotonic()
            self._timer = self.timer_factory(max(.01, delay), self._expire)
            self._timer.daemon = True
            self._timer.start()

    def _expire(self):
        # Physical expiry runs even when a caller disappears without release.
        with self._lock:
            self._timer = None
            self._expire_locked()
            self._schedule_locked()

    def register(self, source):
        source = checked_thumbnail_url(source)
        if source is None:
            return None
        with self._lock:
            self._expire_locked()
            if self._closed or len(self._entries) >= MAX_TOKENS:
                return None
            token = secrets.token_hex(32)
            # Unpredictable tokens are independent of query and destination.
            if token in self._entries:
                return None
            expires = self.clock() + TOKEN_TTL_SECONDS
            self._entries[token] = _Entry(source, self.monotonic() + TOKEN_TTL_SECONDS, expires)
            self._counts['registered'] += 1
            self._schedule_locked()
            return {'token': token, 'expiresAt': datetime.fromtimestamp(expires, timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}

    @staticmethod
    def _token(raw):
        if (not isinstance(raw, dict) or set(raw) != {'token'} or not isinstance(raw['token'], str)
                or not TOKEN_PATTERN.fullmatch(raw['token'])):
            raise SearchError('thumbnail-unavailable', 404)
        return raw['token']

    def fetch(self, raw):
        token = self._token(raw)
        with self._lock:
            self._expire_locked()
            entry = self._entries.get(token)
            if self._closed or entry is None or entry.consumed:
                raise SearchError('thumbnail-unavailable', 404)
            source = entry.source
            entry.source, entry.consumed = None, True
            self._counts['consumed'] += 1
        # Consume before concurrency check, fetch or decode. Failure is final.
        if not self._slots.acquire(blocking=False):
            with self._lock:
                self._counts['failed'] += 1
            raise SearchError('thumbnail-unavailable', 404)
        try:
            if self.fixture:
                image = Image.new('RGB', (96, 64), '#355c7d')
                output = io.BytesIO()
                image.save(output, format='PNG')
                data, mime = output.getvalue(), 'image/png'
            else:
                with self._lock:
                    self._counts['upstream_attempts'] += 1
                data, mime = self.transport.fetch(source)
            png = sanitize_png(data, mime)
            with self._lock:
                self._expire_locked()
                if self._closed or self._entries.get(token) is not entry:
                    raise ValueError('thumbnail-unavailable')
                self._counts['delivered'] += 1
            return png, 'image/png'
        except Exception:
            with self._lock:
                self._counts['failed'] += 1
            raise SearchError('thumbnail-unavailable', 404) from None
        finally:
            self._slots.release()

    def release(self, raw):
        if (not isinstance(raw, dict) or set(raw) != {'tokens'} or not isinstance(raw['tokens'], list)
                or len(raw['tokens']) > 50 or any(not isinstance(token, str) or not TOKEN_PATTERN.fullmatch(token)
                                                for token in raw['tokens'])):
            raise SearchError('invalid-request', 400)
        with self._lock:
            self._expire_locked()
            for token in raw['tokens']:
                if self._entries.pop(token, None) is not None:
                    self._counts['released'] += 1
        return {'schemaVersion': 1, 'status': 'ok'}

    def snapshot(self):
        with self._lock:
            self._expire_locked()
            return dict({name: self._counts[name] for name in
                ('registered', 'consumed', 'upstream_attempts', 'delivered', 'failed', 'released', 'expired')},
                active_tokens=len(self._entries), fixture=self.fixture, scope='local-process')

    def close(self):
        with self._lock:
            self._closed = True
            self._entries.clear()
            if self._timer is not None:
                self._timer.cancel()
                self._timer = None
