import json
import unittest
from wingman_search.contracts import SearchError, SearchRequest, parse_results
from wingman_search.policy import SearchPolicy, query_allowed, ad_context
from wingman_search.provider import BraveProvider, BraveTransport, FixtureProvider
from wingman_content.fetch import FetchResult

class LedgerDouble:
    def __init__(self):
        self.events = []
    def reserve(self, endpoint):
        self.events.append(('reserve', endpoint))
        return 1
    def complete(self, reservation, **fields):
        self.events.append(('complete', fields))

class BraveContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = SearchPolicy()

    def test_strict_endpoint_specific_parameters(self):
        for kind in ('web', 'news'):
            r = SearchRequest.parse({'query': 'Python documentation', 'kind': kind})
            p = r.provider_params(1)
            self.assertEqual('strict', p['safesearch'])
            self.assertEqual(0, p['offset'])
            self.assertEqual(1, p['count'])
            self.assertEqual(kind == 'web', 'result_filter' in p)
            self.assertFalse({'summary', 'extra_snippets', 'headers', 'url'} & p.keys())

    def test_validate_without_silently_shortening(self):
        for q in ('', 'x' * 401, 'word ' * 51, 'hello\nworld', '\ud800'):
            with self.assertRaises(SearchError):
                SearchRequest.parse({'query': q})
        self.assertEqual('  science  ', SearchRequest.parse({'query': '  science  '}).query)
        for extra in ({'safesearch': 'off'}, {'offset': True}, {'offset': 10}, {'country': 'ZZ'}, {'headers': {}}, {'url': 'https://example.org'}):
            with self.assertRaises(SearchError):
                SearchRequest.parse(dict(query='science', **extra))
        self.assertNotIn('science', repr(SearchRequest('science')))

    def test_mandatory_queries_and_legitimate_help(self):
        for q in ('buy casino bonus', 'watch porn', 'p.o.r.n', 'p0rn', 'buy vape online', 'buy cannabis research', 'safesearch=off', 'safesearch=0', 'safesearch=%30'):
            self.assertFalse(query_allowed(q), q)
        for q in ('gambling addiction help', 'tobacco cessation', 'medical education', 'breast cancer treatment'):
            self.assertTrue(query_allowed(q), q)
            self.assertIsNone(ad_context(q))
        self.assertEqual('office', ad_context('best office chairs'))
        self.assertIsNone(ad_context('best office chairs for cancer patients'))
        self.assertIsNone(ad_context('best office chairs', altered='casino'))

    def test_different_arrays_plain_text_no_assets_or_altered_query(self):
        row = {'title': '<b>Python</b><script>evil()</script>', 'url': 'https://docs.python.org/3/',
               'description': 'Read <em>documentation</em>.', 'thumbnail': {'src': 'https://tracker.example/pixel'}}
        for kind in ('web', 'news'):
            raw = {'query': {'altered': 'something else'}}
            raw.update({'web': {'results': [row]}} if kind == 'web' else {'results': [row]})
            dto, intent = parse_results(json.dumps(raw).encode(), SearchRequest('best office chairs', kind), self.policy)
            self.assertEqual('Python', dto['results'][0]['title'])
            self.assertNotIn('thumbnail', json.dumps(dto))
            self.assertNotIn('something else', json.dumps(dto))
            self.assertIsNone(intent)
        with self.assertRaises(SearchError):
            parse_results(b'{"web":{"results":[]}}', SearchRequest('science', 'news'), self.policy)

    def test_malicious_results_filtered_and_duplicate_json_denied(self):
        for url in ('javascript:alert(1)', 'http://example.org', 'https://user:pass@example.org', 'https://127.0.0.1/',
                    'https://foo.local/', 'https://example.org/%252e%252e/admin', 'https://gambling.protection.test/'):
            self.assertFalse(self.policy.allows_url(url), url)
        raw = {'web': {'results': [{'title': 'casino bonus', 'url': 'https://example.org/', 'description': 'buy now'}]}}
        dto, _ = parse_results(json.dumps(raw).encode(), SearchRequest('science'), self.policy)
        self.assertEqual('filtered', dto['status'])
        with self.assertRaises(SearchError):
            parse_results(b'{"web":{"results":[],"results":[]}}', SearchRequest('science'), self.policy)

    def test_fixture_is_labeled_no_transport(self):
        dto, _ = FixtureProvider(self.policy).search(SearchRequest('science'))
        self.assertTrue(dto['fixture'])
        self.assertTrue(all(i['title'].startswith('Fixture:') for i in dto['results']))

    def test_category_paths_reject_encoded_and_duplicate_slash_variants(self):
        for path in ('/espn/betting', '//espn/betting', '/%2fespn/betting', '/%252fespn/betting',
                     '/espn/%2562etting', '/%25252fespn/betting'):
            self.assertFalse(self.policy.allows_url('https://espn.com' + path), path)

    def test_reserve_before_dispatch_and_sanitized_failures(self):
        ledger = LedgerDouble()
        class Transport:
            def request(self, kind, params, key):
                self_outer.assertEqual([('reserve', 'web')], ledger.events)
                raise RuntimeError('https://provider.example/?q=CANARY_SECRET_QUERY token=NEVER_PRINT')
        self_outer = self
        provider = BraveProvider(ledger, 'fixture-token', transport=Transport(), policy=self.policy)
        with self.assertRaises(SearchError) as ctx:
            provider.search(SearchRequest('science'))
        self.assertEqual('transport-error', str(ctx.exception))
        self.assertIsNone(ctx.exception.__cause__)
        self.assertEqual('transport_error', ledger.events[-1][1]['status_class'])
        self.assertNotIn('science', str(ledger.events))

    def test_success_http_but_malformed_schema_accounted_separately(self):
        ledger = LedgerDouble()
        class Transport:
            def request(self, *args):
                return FetchResult(200, {}, b'not json')
        with self.assertRaises(SearchError):
            BraveProvider(ledger, 'fixture-token', transport=Transport(), policy=self.policy).search(SearchRequest('science'))
        self.assertEqual('malformed_response', ledger.events[-1][1]['status_class'])
        self.assertEqual(200, ledger.events[-1][1]['http_status'])

    def test_http_failures_do_not_retry(self):
        for status, code in ((401, 'provider-authentication'), (403, 'provider-entitlement'),
                             (429, 'provider-rate-limited'), (500, 'provider-unavailable')):
            ledger = LedgerDouble()
            class Transport:
                def request(self, *args):
                    return FetchResult(status, {'retry-after': '60'}, b'query-bearing error body')
            with self.assertRaises(SearchError) as ctx:
                BraveProvider(ledger, 'fixture-token', transport=Transport(), policy=self.policy).search(SearchRequest('science'))
            self.assertEqual(code, ctx.exception.code)
            self.assertEqual(2, len(ledger.events))

    def test_invalid_alteration_and_private_never_yield_ad_context(self):
        for altered in (False, 1, [], {}, 'casino'):
            raw = {'query': {'altered': altered}, 'web': {'results': [
                {'title': 'Office chair', 'url': 'https://example.org/', 'description': 'Office furniture'}]}}
            _, intent = parse_results(json.dumps(raw).encode(), SearchRequest('best office chairs'), self.policy)
            self.assertIsNone(intent)
        raw['query'] = {}
        _, intent = parse_results(json.dumps(raw).encode(), SearchRequest('best office chairs', context='private'), self.policy)
        self.assertIsNone(intent)

    def test_timestamp_overflow_finalizes_received_success_as_schema_failure(self):
        ledger = LedgerDouble()
        class Transport:
            def request(self, *args):
                return FetchResult(200, {}, json.dumps({'results': [{'title': 'Science', 'url': 'https://example.org/',
                    'page_age': '0001-01-01T00:00:00+01:00'}]}).encode())
        with self.assertRaises(SearchError) as ctx:
            BraveProvider(ledger, 'fixture-token', transport=Transport(), policy=self.policy).search(SearchRequest('science', 'news'))
        self.assertEqual(200, ctx.exception.provider_status)
        self.assertEqual('malformed_response', ledger.events[-1][1]['status_class'])

    def test_transport_fixed_headers_no_redirect(self):
        events = []
        class Reply:
            status = 302
            def getheaders(self):
                return [('Location', 'https://untrusted.example/'), ('Set-Cookie', 'tracking=yes')]
        class Connection:
            sock = None
            def __init__(self, host, address, timeout):
                events.append((host, address))
            def request(self, method, path, headers):
                events.append((method, path, set(headers)))
            def getresponse(self):
                return Reply()
            def close(self):
                pass
        reply = BraveTransport(resolver=lambda *_: ['8.8.8.8'], connector=Connection).request(
            'web', SearchRequest('science').provider_params(1), 'fixture-token')
        self.assertEqual(302, reply.status)
        self.assertEqual({}, reply.headers)
        self.assertEqual('api.search.brave.com', events[0][0])
        self.assertIn('safesearch=strict', events[1][1])
        self.assertFalse({'Cookie', 'Authorization', 'X-Forwarded-For', 'Referer'} & events[1][2])

if __name__ == '__main__':
    unittest.main()
