"""Brave's two organic endpoints, with one shared dispatch accounting boundary."""
import json
import socket
import threading
import time
from urllib.parse import urlencode
from wingman_content.fetch import PinnedHTTPSConnection, resolve_public, public_ip, FetchResult
from .contracts import SearchRequest, SearchError, parse_results
from .policy import SearchPolicy

HOST = 'api.search.brave.com'
PATHS = {'web': '/res/v1/web/search', 'news': '/res/v1/news/search'}

class BraveTransport:
    """Fixed HTTPS host, public address pinning, bounded I/O, no redirects/retry."""
    def __init__(self, resolver=resolve_public, connector=PinnedHTTPSConnection):
        self.resolver, self.connector = resolver, connector

    def request(self, kind, params, key):
        connection, timer, status, headers = None, None, None, {}
        deadline = time.monotonic() + 12
        try:
            addresses = self.resolver(HOST, 3)
            if not addresses or any(not public_ip(a) for a in addresses):
                raise ValueError()
            connection = self.connector(HOST, addresses[0], 5)
            def stop():
                if connection.sock:
                    try:
                        connection.sock.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    connection.sock.close()
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
                return FetchResult(status, {}, b'')
            for k, v in pairs:
                k = k.lower()
                if k in headers:
                    return FetchResult(status, {}, b'')
                # Keep only operational metadata. Do not retain cookies or locations.
                if k in ('content-type', 'content-length', 'content-encoding', 'retry-after',
                         'x-ratelimit-limit', 'x-ratelimit-policy', 'x-ratelimit-remaining', 'x-ratelimit-reset'):
                    headers[k] = v
            if status != 200:
                return FetchResult(status, headers, b'')
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
            return FetchResult(status, headers, b'')
        except Exception:
            if status is not None:
                return FetchResult(status, headers, b'')
            # Original exceptions may contain query URLs. Never chain/return them.
            raise SearchError('transport-error', 503) from None
        finally:
            if timer:
                timer.cancel()
            if connection:
                try:
                    connection.close()
                except Exception:
                    pass

class BraveProvider:
    def __init__(self, ledger, key, *, transport=None, policy=None):
        self.ledger, self._key = ledger, key
        self.transport, self.policy = transport or BraveTransport(), policy or SearchPolicy()
        self.before_request = None

    def search(self, request, *, count=20):
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
        except Exception:
            self.ledger.complete(reservation, status_class='transport_error')
            raise SearchError('transport-error', 503) from None
        headers = reply.headers
        if reply.status != 200:
            category = ('auth_error' if reply.status in (401, 403) else
                        'rate_limited' if reply.status == 429 else 'http_error')
            self.ledger.complete(reservation, status_class=category, http_status=reply.status,
                                 rate_limit_headers=headers)
            code = ('provider-authentication' if reply.status == 401 else
                    'provider-entitlement' if reply.status in (402, 403) else
                    'provider-rate-limited' if reply.status == 429 else 'provider-unavailable')
            raise SearchError(code, 503, reply.status)
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
