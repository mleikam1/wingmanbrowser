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

if __name__ == '__main__':
    unittest.main()
