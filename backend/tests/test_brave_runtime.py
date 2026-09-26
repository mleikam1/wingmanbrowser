import io
import json
from pathlib import Path
import tempfile
import unittest
from wingman_search.config import SearchConfig, ConfigurationError, GATES
from wingman_search.runtime import create_brave_provider, DurableSearchMetrics, read_config
from wingman_search.wsgi import SearchWSGI
from wingman_search.provider import FixtureProvider
from wingman_search.gateway import SearchApplication
from wingman_search.budget import BudgetError


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'rights.json'
        self.rights = {'schema_version': 1, 'approved_domains': ['gateway.wingman.org'], 'gates': {
            gate: {'enabled': gate == 'live_search', 'authorization_status': 'approved',
                   'evidence_reference': 'fixture-only'} for gate in GATES}}
        self.path.write_text(json.dumps(self.rights))
        self.config = SearchConfig(profile='production', environment='production', live_search=True,
            production_gateway_url='https://gateway.wingman.org/v1/search', shared_ledger_kind='gcs',
            shared_project='wingman-fixture', shared_bucket='wingman-fixture-bucket',
            deployment_approval_reference='fixture-only', provider_spend_approval_reference='fixture-only',
            secret_manager_reference='projects/wingman-fixture/secrets/fixture/versions/1',
            production_cap_micros=10000, rights_register_path=str(self.path))
    def tearDown(self):
        self.temp.cleanup()
    def test_default_never_constructs_cloud_or_loads_secret(self):
        calls = []
        with self.assertRaises(ConfigurationError):
            create_brave_provider(SearchConfig(), ledger_factory=lambda **kw: calls.append(kw),
                                  secret_loader=lambda name: calls.append(name))
        self.assertEqual([], calls)
    def test_cap_mismatch_precedes_secret_read(self):
        class Ledger:
            def __init__(self, **kw): pass
            def snapshot(self): return {'global_cap_micros': 50000}
        calls = []
        with self.assertRaises(BudgetError):
            create_brave_provider(self.config, ledger_factory=Ledger, secret_loader=lambda n: calls.append(n))
        self.assertEqual([], calls)
    def test_rights_revocation_precedes_reservation(self):
        calls = []
        class Ledger:
            def __init__(self, **kw): pass
            def snapshot(self): return {'global_cap_micros': 10000, 'unit_cost_micros': 5000,
                'approval_reference': 'fixture-only', 'profile': 'approved-production', 'environment': 'production'}
            def reserve(self, kind): calls.append(kind)
        provider = create_brave_provider(self.config, ledger_factory=Ledger,
                                         secret_loader=lambda _: 'fixture-token-only')
        self.rights['gates']['live_search']['enabled'] = False
        self.path.write_text(json.dumps(self.rights))
        from wingman_search.contracts import SearchRequest
        with self.assertRaises(ConfigurationError):
            provider.search(SearchRequest('science'))
        self.assertEqual([], calls)
    def test_billing_is_independent_and_unknown_config_rejected(self):
        self.config.validate()
        self.assertFalse(self.config.production_billing)
        path = Path(self.temp.name) / 'config.json'
        path.write_text('{"profile":"fixtures", "key":"not-accepted"}')
        with self.assertRaises(ConfigurationError): read_config(path)
    def test_wsgi_exact_routes_host_origin_framing_and_no_history(self):
        app = SearchWSGI(SearchApplication(FixtureProvider()), self.config)
        body = json.dumps({'query': 'UNIQUE_TRANSIENT_CANARY'}).encode()
        base = {'REQUEST_METHOD': 'POST', 'PATH_INFO': '/v1/search', 'QUERY_STRING': '',
            'HTTP_HOST': 'gateway.wingman.org', 'wsgi.url_scheme': 'https',
            'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(body))}
        def call(**updates):
            output = []
            result = app(dict(base, **{'wsgi.input': io.BytesIO(body)}, **updates),
                         lambda status, headers: output.append((status, dict(headers))))
            return output[0], b''.join(result)
        (status, headers), data = call(HTTP_ORIGIN='https://gateway.wingman.org')
        self.assertTrue(status.startswith('200'))
        self.assertEqual('no-referrer', headers['Referrer-Policy'])
        self.assertNotIn(b'UNIQUE_TRANSIENT_CANARY', data)
        for update in ({'HTTP_ORIGIN': 'https://evil.org'}, {'HTTP_HOST': 'evil.org'},
                       {'wsgi.url_scheme': 'http'}, {'QUERY_STRING': 'q=science'},
                       {'HTTP_TRANSFER_ENCODING': 'chunked'}, {'CONTENT_LENGTH': '999999'},
                       {'PATH_INFO': '/admin'}, {'REQUEST_METHOD': 'GET'}):
            self.assertFalse(call(**update)[0][0].startswith('200'))
    def test_durable_metric_adapter_has_finite_ledger_boundary(self):
        class Ledger:
            def record_search_event(self, name): self.name = name
            def search_metrics(self): return {'submitted': 1, 'durable': True}
        ledger = Ledger()
        metrics = DurableSearchMetrics(ledger)
        metrics.add('submitted')
        self.assertEqual('submitted', ledger.name)
        self.assertTrue(metrics.snapshot()['durable'])


if __name__ == '__main__': unittest.main()
