import contextlib
import http.client
import io
import json
import threading
import unittest
from wingman_search.gateway import SearchApplication, LocalServer, handler_for, BurstGuard
from wingman_search.provider import FixtureProvider

class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.app = SearchApplication(FixtureProvider())
        self.server = LocalServer(('127.0.0.1', 0), handler_for(self.app, ['http://127.0.0.1:8894']))
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
    def call(self, method='POST', path='/v1/search', raw=None, headers=None):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        body = json.dumps(raw or {'query': 'science'})
        c.request(method, path, body=body if method == 'POST' else None,
                  headers={'Content-Type': 'application/json', **(headers or {})})
        reply = c.getresponse()
        result = (reply.status, dict(reply.getheaders()), reply.read())
        c.close()
        return result
    def test_search_post_no_cache_no_referrer(self):
        status, headers, data = self.call(headers={'Origin': 'http://127.0.0.1:8894'})
        self.assertEqual(200, status)
        self.assertTrue(json.loads(data)['fixture'])
        self.assertIn('no-store', headers['Cache-Control'])
        self.assertEqual('no-referrer', headers['Referrer-Policy'])
        self.assertEqual('http://127.0.0.1:8894', headers['Access-Control-Allow-Origin'])
    def test_no_get_search_or_query_url(self):
        self.assertEqual(404, self.call('GET', '/v1/search?q=science')[0])
        self.assertEqual(404, self.call(path='/v1/search?q=science')[0])
        self.assertEqual(404, self.call('HEAD')[0])
        self.assertNotIn('submitted', self.app.metrics.snapshot())
    def test_arbitrary_origin_host_params_and_managed_denied(self):
        self.assertEqual(403, self.call(headers={'Origin': 'https://evil.example'})[0])
        self.assertEqual(403, self.call(headers={'Host': 'evil.example'})[0])
        self.assertEqual(400, self.call(raw={'query': 'science', 'safesearch': 'off'})[0])
        self.assertEqual(403, self.call(raw={'query': 'science', 'context': 'managed'})[0])
        self.assertEqual(403, self.call(raw={'query': 'casino bonus'})[0])
    def test_no_query_in_logs_or_metrics(self):
        canary = 'UNIQUE_PRIVACY_CANARY_DO_NOT_PERSIST'
        log = io.StringIO()
        with contextlib.redirect_stderr(log), contextlib.redirect_stdout(log):
            status, _, body = self.call(raw={'query': canary})
        self.assertEqual(200, status)
        self.assertNotIn(canary, body.decode())
        self.assertNotIn(canary, log.getvalue())
        self.assertNotIn(canary, json.dumps(self.app.metrics.snapshot()))
    def test_unconfigured_has_no_fallback(self):
        from wingman_search.contracts import SearchError
        with self.assertRaises(SearchError) as caught:
            SearchApplication().search({'query': 'science'})
        self.assertEqual('configuration-required', caught.exception.code)
    def test_burst_counter_ttl(self):
        clock = [0]
        guard = BurstGuard(limit=2, clock=lambda: clock[0])
        self.assertTrue(guard.allow('127.0.0.1'))
        self.assertTrue(guard.allow('127.0.0.1'))
        self.assertFalse(guard.allow('127.0.0.1'))
        clock[0] = 61
        self.assertTrue(guard.allow('127.0.0.1'))
        self.assertNotIn('127.0.0.1', repr(guard.__dict__))

    def test_outcome_metric_failure_does_not_trigger_paid_retry_or_mask_error(self):
        from wingman_search.budget import BudgetError
        from wingman_search.contracts import SearchError
        class Metrics:
            def add(self, name):
                if name in ('completed', 'failed'):
                    raise BudgetError('shared_ledger_unavailable')
        app = SearchApplication(FixtureProvider(), metrics=Metrics())
        self.assertTrue(app.search({'query': 'science'})['fixture'])
        self.assertTrue(app.outcome_metrics_degraded)
        with self.assertRaises(SearchError) as caught:
            app.search({'query': 'science', 'context': 'managed'})
        self.assertEqual('managed-search-unavailable', caught.exception.code)

    def test_ad_context_is_separate_nonsensitive_normal_initial_page_only(self):
        class Ads:
            def __init__(self): self.calls = []
            def issue_context(self, **kw):
                self.calls.append(kw)
                return {'token': 'fixture-context', 'expiresAt': '2026-09-26T12:00:00Z'}
        ads = Ads()
        app = SearchApplication(FixtureProvider(), ads=ads)
        self.assertIn('adContext', app.search({'query': 'best office chairs'}))
        self.assertEqual([{'intent': 'office', 'country': 'US', 'language': 'en',
            'context': 'normal', 'fixture': True}], ads.calls)
        for fields in ({'query': 'best office chairs', 'context': 'private'},
                       {'query': 'best office chairs', 'offset': 1},
                       {'query': 'best office chairs', 'kind': 'news'},
                       {'query': 'medical research'}, {'query': 'science'}):
            self.assertNotIn('adContext', app.search(fields))
        self.assertEqual(1, len(ads.calls))

    def test_ad_signing_failure_preserves_organic_and_default_no_fill(self):
        class Ads:
            def issue_context(self, **kw): raise RuntimeError('fixture-only')
        self.assertTrue(SearchApplication(FixtureProvider(), ads=Ads()).search(
            {'query': 'best office chairs'})['results'])
        status, headers, body = self.call(path='/v1/ads/decision', raw={'placement': 'search'})
        self.assertEqual(200, status)
        self.assertEqual('no-fill', json.loads(body)['status'])
        self.assertIn('no-store', headers['Cache-Control'])
        self.assertEqual(404, self.call('GET', '/v1/ads/event')[0])
        self.assertEqual(404, self.call('HEAD', '/v1/ads/event')[0])
        self.assertEqual(0, json.loads(self.call(path='/v1/ads/event', raw={'kind': 'click'})[2])['chargedMicros'])

if __name__ == '__main__':
    unittest.main()
