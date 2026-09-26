"""Brave's two organic endpoints, with one shared dispatch accounting boundary."""
from __future__ import annotations
import json
from dataclasses import dataclass
import ssl
import socket
import threading
import time
from urllib.parse import urlencode
from wingman_content.fetch import PinnedHTTPSConnection, resolve_public, public_ip, FetchResult, FetchError
from .contracts import SearchRequest, SearchError, parse_results, decode_json
from .policy import SearchPolicy

HOST = 'api.search.brave.com'
PATHS = {'web': '/res/v1/web/search', 'news': '/res/v1/news/search'}

TRANSPORT_CODES = frozenset({'transport-dns', 'transport-tls',
    'transport-connection', 'transport-timeout', 'transport-error'})
# Only exact documented enums may leave a bounded provider error body.
PROVIDER_ERROR_CODES = frozenset({'INTERNAL', 'QUOTA_LIMITED', 'RATE_LIMITED'})

@dataclass(repr=False)
class BraveReply:
    status: int
    headers: dict
    body: bytes
    failure_code: str | None = None
    provider_code: str | None = None

class TransportFailure(SearchError):
    def __init__(self, code):
        super().__init__(code if code in TRANSPORT_CODES else 'transport-error', 503)

def _transport_code(error, stage):
    if isinstance(error, (TimeoutError, socket.timeout)):
        return 'transport-timeout'
    if isinstance(error, ssl.SSLError):
        return 'transport-tls'
    if isinstance(error, FetchError) and error.reason == 'dns-timeout':
        return 'transport-timeout'
    if stage == 'dns' or isinstance(error, socket.gaierror):
        return 'transport-dns'
    if isinstance(error, (ConnectionError, OSError)):
        return 'transport-connection'
    return 'transport-error'

def _safe_provider_error(response, headers, deadline):
    # Inspect only a small JSON error in memory. Discard detail/meta/id/query.
    if (headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json'
            or headers.get('content-encoding', 'identity').lower() not in ('identity', '')):
        return None
    maximum = 16 * 1024
    length = headers.get('content-length')
    if length is not None and (not length.isdecimal() or len(length) > 8 or int(length) > maximum):
        return None
    body = bytearray()
    try:
        while time.monotonic() < deadline:
            chunk = response.read(min(4096, maximum + 1 - len(body)))
            if not chunk:
                raw = decode_json(bytes(body), maximum)
                error = raw.get('error') if isinstance(raw, dict) else None
                code = error.get('code') if isinstance(error, dict) else None
                return code if isinstance(code, str) and code in PROVIDER_ERROR_CODES else None
            body.extend(chunk)
            if len(body) > maximum:
                return None
    except Exception:
        pass
    return None

class BraveTransport:
    """Fixed HTTPS host, public address pinning, bounded I/O, no redirects/retry."""
    def __init__(self, resolver=resolve_public, connector=PinnedHTTPSConnection):
        self.resolver, self.connector = resolver, connector

    def request(self, kind, params, key):
        connection, timer, status, headers = None, None, None, {}
        stage = 'dns'
        deadline = time.monotonic() + 12
        try:
            addresses = self.resolver(HOST, 3)
            if not addresses or any(not public_ip(a) for a in addresses):
                raise ValueError()
            stage = 'connection'
            connection = self.connector(HOST, addresses[0], 5)
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
            connection.request('GET', PATHS[kind] + '?' + urlencode(params), headers={
                'X-Subscription-Token': key, 'Accept': 'application/json',
                'Accept-Encoding': 'identity', 'User-Agent': 'WingmanSearch/1.0', 'Connection': 'close'})
            response = connection.getresponse()
            status = response.status
            pairs = response.getheaders()
            if sum(len(k) + len(v) for k, v in pairs) > 32768:
                # Ambiguous/discarded metadata cannot mean "no rate limit".
                # This reviewed sentinel makes both ledgers halt while retaining
                # the received status for conservative versus confirmed charges.
                return FetchResult(status, {'x-ratelimit-limit': 'invalid'}, b'')
            for k, v in pairs:
                k = k.lower()
                if k in headers:
                    return FetchResult(status, {'x-ratelimit-limit': 'invalid'}, b'')
                # Keep only operational metadata. Do not retain cookies or locations.
                if k in ('content-type', 'content-length', 'content-encoding', 'retry-after',
                         'x-ratelimit-limit', 'x-ratelimit-policy', 'x-ratelimit-remaining', 'x-ratelimit-reset'):
                    headers[k] = v
            if status != 200:
                code = _safe_provider_error(response, headers, deadline) if 400 <= status <= 599 else None
                return BraveReply(status, headers, b'', provider_code=code)
            if (headers.get('content-type', '').split(';')[0].strip().lower() != 'application/json'
                    or headers.get('content-encoding', 'identity').lower() not in ('identity', '')):
                return FetchResult(status, headers, b'')
            length = headers.get('content-length')
            if length is not None and (not length.isdecimal() or len(length) > 9 or int(length) > 1024 * 1024):
                return FetchResult(status, headers, b'')
            body = bytearray()
            while time.monotonic() < deadline:
                chunk = response.read(min(16384, 1024 * 1024 + 1 - len(body)))
                if not chunk:
                    return FetchResult(status, headers, bytes(body))
                body.extend(chunk)
                if len(body) > 1024 * 1024:
                    break
            return BraveReply(status, headers, b'',
                failure_code='transport-timeout' if time.monotonic() >= deadline else None)
        except Exception as error:
            code = ('transport-timeout' if time.monotonic() >= deadline
                    else _transport_code(error, stage))
            if status is not None:
                return BraveReply(status, headers, b'', failure_code=code)
            # Original exceptions may contain query URLs. Never chain/return them.
            raise TransportFailure(code) from None
        finally:
            if timer:
                timer.cancel()
            if connection:
                try:
                    connection.close()
                except Exception:
                    pass

class BraveProvider:
    def __init__(self, ledger, key, *, transport=None, policy=None, default_count=20):
        self.ledger, self._key = ledger, key
        self.transport, self.policy = transport or BraveTransport(), policy or SearchPolicy()
        self.before_request = None
        if type(default_count) is not int or not 1 <= default_count <= 20:
            raise SearchError('invalid-count')
        self.default_count = default_count

    def search(self, request, *, count=None):
        count = self.default_count if count is None else count
        # Reparse even typed callers; constructing a dataclass grants no bypass.
        request = SearchRequest.parse(dict(query=request.query, kind=request.kind, country=request.country,
            searchLang=request.search_lang, uiLang=request.ui_lang, offset=request.offset, context=request.context))
        params = request.provider_params(count)
        if (not isinstance(self._key, str) or not 1 <= len(self._key) <= 4096
                or not self._key.isascii() or any(ord(c) < 33 or ord(c) > 126 for c in self._key)):
            raise SearchError('configuration-required', 503)
        if self.before_request:
            self.before_request()
        reservation = self.ledger.reserve(request.kind)
        try:
            reply = self.transport.request(request.kind, params, self._key)
        except Exception as error:
            self.ledger.complete(reservation, status_class='transport_error')
            code = error.code if isinstance(error, TransportFailure) else 'transport-error'
            raise SearchError(code, 503) from None
        headers = reply.headers
        if reply.status != 200:
            category = ('auth_error' if reply.status in (401, 402, 403) else
                        'rate_limited' if reply.status == 429 else 'http_error')
            self.ledger.complete(reservation, status_class=category, http_status=reply.status,
                                 rate_limit_headers=headers)
            code = ('provider-authentication' if reply.status == 401 else
                    'provider-entitlement' if reply.status in (402, 403) else
                    'provider-rate-limited' if reply.status == 429 else
                    'provider-request-invalid' if reply.status in (400, 422) else 'provider-unavailable')
            raise SearchError(code, 503, reply.status, provider_code=getattr(reply, 'provider_code', None))
        if getattr(reply, 'failure_code', None) in TRANSPORT_CODES:
            self.ledger.complete(reservation, status_class='transport_error', http_status=reply.status,
                                 rate_limit_headers=headers)
            raise SearchError(reply.failure_code, 503, reply.status)
        try:
            result = parse_results(reply.body, request, self.policy, count=count)
        except Exception:
            self.ledger.complete(reservation, status_class='malformed_response', http_status=200,
                                 rate_limit_headers=headers)
            raise SearchError('malformed-response', 502, 200) from None
        self.ledger.complete(reservation, status_class='success', http_status=200, rate_limit_headers=headers)
        return result

class FixtureProvider:
    """Synthetic contract fixtures; never creates transport or loads a secret."""
    def __init__(self, policy=None):
        self.policy = policy or SearchPolicy()

    def search(self, request, *, count=20):
        request = SearchRequest.parse(dict(query=request.query, kind=request.kind, country=request.country,
            searchLang=request.search_lang, uiLang=request.ui_lang, offset=request.offset, context=request.context))
        rows = [dict(title='Fixture: Python documentation', url='https://docs.python.org/3/',
                     description='Synthetic integration fixture. Learn about Python language features.'),
                dict(title='Fixture: NASA Moon science', url='https://www.nasa.gov/moon/',
                     description='Synthetic integration fixture for protected Wingman navigation.')]
        if request.kind == 'news':
            rows = [dict(title='Fixture: Space research update', url='https://www.nasa.gov/news/',
                         description='Synthetic news card. Publication time is unknown.')]
        if request.offset:
            rows = []
        raw = {'query': {'more_results_available': False}}
        raw.update({'web': {'results': rows[:count]}} if request.kind == 'web' else {'results': rows[:count]})
        return parse_results(json.dumps(raw).encode(), request, self.policy, count=count, fixture=True)
