"""Offline probes of live adapter error boundaries; no provider requests."""
import io
import json
import socket
import ssl
import unittest
from unittest.mock import patch

from wingman_content.fetch import FetchError, FetchResult
from wingman_search.contracts import SearchError, SearchRequest
from wingman_search.provider import BraveProvider, BraveTransport, TransportFailure


class Ledger:
    def __init__(self):
        self.events = []

    def reserve(self, kind):
        self.events.append(('reserve', kind))
        return 1

    def complete(self, reservation, **outcome):
        self.events.append(('complete', outcome))


class Response:
    def __init__(self, status, body=b'', *, error=None, headers=None):
        self.status, self.body, self.error = status, io.BytesIO(body), error
        self.headers = headers or [('Content-Type', 'application/json')]
        self.bytes_read = 0

    def getheaders(self):
        return self.headers

    def read(self, size):
        if self.error:
            raise self.error
        value = self.body.read(size)
        self.bytes_read += len(value)
        return value


def transport(response=None, *, request_error=None, resolver=None):
    class Connection:
        sock = None

        def __init__(self, *args):
            pass

        def request(self, *args, **kwargs):
            if request_error:
                raise request_error

        def getresponse(self):
            return response

        def close(self):
            pass
    return BraveTransport(resolver=resolver or (lambda *_: ['8.8.8.8']), connector=Connection)


class LiveTransportTests(unittest.TestCase):
    def test_network_classes_are_safe_and_never_called_invalid_credentials(self):
        cases = [(ssl.SSLCertVerificationError('SECRET query'), 'transport-tls'),
                 (ConnectionRefusedError('SECRET query'), 'transport-connection'),
                 (socket.timeout('SECRET query'), 'transport-timeout')]
        for error, expected in cases:
            with self.subTest(expected=expected):
                ledger = Ledger()
                provider = BraveProvider(ledger, 'fixture-only-key', transport=transport(request_error=error))
                with self.assertRaises(SearchError) as caught:
                    provider.search(SearchRequest('science'))
                self.assertEqual(expected, str(caught.exception))
                self.assertIsNone(caught.exception.provider_status)
                self.assertEqual('transport_error', ledger.events[-1][1]['status_class'])
                self.assertEqual(2, len(ledger.events))

    def test_dns_failure_and_timeout_are_distinct_and_sanitized(self):
        for error, code in [(socket.gaierror('SECRET'), 'transport-dns'),
                            (FetchError('dns-timeout'), 'transport-timeout')]:
            def resolver(*args):
                raise error
            with self.assertRaises(TransportFailure) as caught:
                transport(resolver=resolver).request('web', {}, 'fixture-only-key')
            self.assertEqual(code, str(caught.exception))
            self.assertIsNone(caught.exception.__cause__)

    def test_deadline_socket_close_is_timeout_even_with_connection_exception(self):
        with patch('wingman_search.provider.time.monotonic', side_effect=[0, 0, 13]):
            with self.assertRaises(TransportFailure) as caught:
                transport(request_error=ConnectionResetError('SECRET')).request('web', {}, 'fixture-only-key')
        self.assertEqual('transport-timeout', caught.exception.code)

    def test_received_http_200_read_timeout_keeps_status_and_real_cause(self):
        ledger = Ledger()
        provider = BraveProvider(ledger, 'fixture-only-key',
            transport=transport(Response(200, error=TimeoutError('SECRET'))))
        with self.assertRaises(SearchError) as caught:
            provider.search(SearchRequest('science'))
        self.assertEqual('transport-timeout', caught.exception.code)
        self.assertEqual(200, caught.exception.provider_status)
        self.assertEqual(200, ledger.events[-1][1]['http_status'])
        self.assertEqual('transport_error', ledger.events[-1][1]['status_class'])

    def test_non_200_metadata_does_not_reflect_error_detail_or_query(self):
        for code, safe in [('RATE_LIMITED', 'RATE_LIMITED'), ('QUERY_SECRET', None), ({'key': 'SECRET'}, None)]:
            response = Response(429, json.dumps({'error': {'code': code,
                'detail': 'SECRET', 'meta': {'query': 'PRIVATE'}}}).encode())
            reply = transport(response).request('news', {}, 'fixture-only-key')
            self.assertEqual(safe, reply.provider_code)
            self.assertEqual(b'', reply.body)
            self.assertNotIn('SECRET', repr(reply))
            ledger = Ledger()
            class FixedTransport:
                def request(self, *args):
                    return reply
            with self.assertRaises(SearchError) as caught:
                BraveProvider(ledger, 'fixture-only-key', transport=FixedTransport()).search(SearchRequest('science'))
            self.assertEqual(safe, caught.exception.provider_code)
            self.assertEqual('provider-rate-limited', str(caught.exception))

    def test_error_inspection_is_bounded_and_redirect_never_read(self):
        response = Response(422, b'x' * 100000)
        reply = transport(response).request('web', {}, 'fixture-only-key')
        self.assertLessEqual(response.bytes_read, 16385)
        self.assertIsNone(reply.provider_code)
        self.assertEqual(b'', reply.body)
        response = Response(302, b'query secret', headers=[('Location', 'https://evil.example/')])
        reply = transport(response).request('web', {}, 'fixture-only-key')
        self.assertEqual(0, response.bytes_read)
        self.assertNotIn('location', reply.headers)

    def test_status_categories_and_one_attempt_only(self):
        for status, code, category in [(400, 'provider-request-invalid', 'http_error'),
                (422, 'provider-request-invalid', 'http_error'),
                (401, 'provider-authentication', 'auth_error'),
                (402, 'provider-entitlement', 'auth_error'),
                (403, 'provider-entitlement', 'auth_error'),
                (429, 'provider-rate-limited', 'rate_limited'),
                (500, 'provider-unavailable', 'http_error')]:
            ledger = Ledger()
            with self.assertRaises(SearchError) as caught:
                BraveProvider(ledger, 'fixture-only-key', transport=transport(Response(status))).search(SearchRequest('science'))
            self.assertEqual(code, caught.exception.code)
            self.assertEqual(status, caught.exception.provider_status)
            self.assertEqual(category, ledger.events[-1][1]['status_class'])
            self.assertEqual(2, len(ledger.events))

    def test_local_default_count_ten_uses_both_current_response_shapes(self):
        ledger = Ledger()
        outer = self
        class FixedTransport:
            def request(self, kind, params, key):
                outer.assertEqual(10, params['count'])
                outer.assertEqual('strict', params['safesearch'])
                outer.assertEqual(kind == 'web', 'text_decorations' in params)
                outer.assertEqual(kind == 'web', 'result_filter' in params)
                row = {'title': 'Science', 'url': 'https://www.nasa.gov/', 'description': None}
                raw = {'web': {'results': [row]}} if kind == 'web' else {'results': [row]}
                return FetchResult(200, {}, json.dumps(raw).encode())
        provider = BraveProvider(ledger, 'fixture-only-key', transport=FixedTransport(), default_count=10)
        self.assertEqual([], ledger.events)
        for kind in ('web', 'news'):
            dto, _ = provider.search(SearchRequest('science', kind))
            self.assertFalse(dto['fixture'])
            self.assertEqual(1, len(dto['results']))

    def test_http_200_empty_filtered_and_invalid_schema_remain_distinct(self):
        for raw, expected in [({'web': {'results': []}}, 'empty'),
                ({'web': {'results': [{'title': 'casino bonus', 'url': 'https://example.org/'}]}}, 'filtered'),
                ({'unexpected': []}, 'malformed-response')]:
            provider = BraveProvider(Ledger(), 'fixture-only-key', transport=transport(Response(200, json.dumps(raw).encode())))
            if expected == 'malformed-response':
                with self.assertRaisesRegex(SearchError, expected):
                    provider.search(SearchRequest('science'))
            else:
                self.assertEqual(expected, provider.search(SearchRequest('science'))[0]['status'])


if __name__ == '__main__':
    unittest.main()
