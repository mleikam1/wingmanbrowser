import io
import json
from pathlib import Path
import tempfile
import unittest
from dataclasses import replace
from wingman_search.config import SearchConfig, ConfigurationError, GATES
from wingman_search.runtime import create_brave_provider, DurableSearchMetrics, read_config, create_search_application, RightsGatedAds
from wingman_search.wsgi import SearchWSGI
from wingman_search.provider import FixtureProvider
from wingman_search.gateway import SearchApplication
from wingman_search.budget import BudgetError
from wingman_content.fetch import FetchResult


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

    def test_wsgi_thumbnail_routes_are_post_only_and_do_not_consume_search_guard(self):
        from unittest.mock import Mock
        from wingman_search.gateway import BurstGuard
        from wingman_search.thumbnails import THUMBNAIL_PATH, RELEASE_PATH
        application = SearchApplication(FixtureProvider())
        application.thumbnail_request = Mock(return_value=(b'bounded-png-fixture', 'image/png'))
        app = SearchWSGI(application, self.config)
        app.guard = BurstGuard(limit=1)
        body = json.dumps({'token': 'a' * 64}).encode()
        base = {'REQUEST_METHOD': 'POST', 'PATH_INFO': THUMBNAIL_PATH, 'QUERY_STRING': '',
            'HTTP_HOST': 'gateway.wingman.org', 'wsgi.url_scheme': 'https',
            'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(body))}
        def call(**updates):
            output = []
            result = app(dict(base, **{'wsgi.input': io.BytesIO(body)}, **updates),
                lambda status, headers: output.append((status, dict(headers))))
            return output[0], b''.join(result)
        (status, headers), data = call(HTTP_ORIGIN='https://gateway.wingman.org')
        self.assertTrue(status.startswith('200'))
        self.assertEqual('image/png', headers['Content-Type'])
        self.assertEqual('no-store, private', headers['Cache-Control'])
        self.assertEqual('no-referrer', headers['Referrer-Policy'])
        self.assertEqual(b'bounded-png-fixture', data)
        self.assertEqual(1, application.thumbnail_request.call_count)
        for update in ({'REQUEST_METHOD': 'GET'}, {'REQUEST_METHOD': 'HEAD'},
                       {'HTTP_ORIGIN': 'https://evil.org'}, {'HTTP_HOST': 'evil.org'},
                       {'HTTP_COOKIE': 'session=fixture'}, {'HTTP_AUTHORIZATION': 'Bearer fixture'},
                       {'HTTP_SEC_FETCH_SITE': 'cross-site'}, {'QUERY_STRING': 'token=fixture'},
                       {'CONTENT_TYPE': 'text/plain'}, {'HTTP_TRANSFER_ENCODING': 'chunked'}):
            self.assertFalse(call(**update)[0][0].startswith('200'))
        self.assertTrue(call(REQUEST_METHOD='OPTIONS')[0][0].startswith('200'))
        self.assertEqual(1, application.thumbnail_request.call_count)
        application.thumbnail_request.return_value = ({'schemaVersion': 1, 'status': 'ok'},
                                                      'application/json; charset=utf-8')
        (status, headers), data = call(PATH_INFO=RELEASE_PATH)
        self.assertTrue(status.startswith('200'))
        self.assertEqual('application/json; charset=utf-8', headers['Content-Type'])
        self.assertEqual('ok', json.loads(data)['status'])
        self.assertEqual({}, {key: value for key, value in application.metrics.snapshot().items()
                             if key not in ('scope', 'durable')})
        self.assertTrue(app.guard.allow(None))
        self.assertFalse(app.guard.allow(None))
        application.close()

    def test_live_ads_require_billing_durable_host_and_independent_rights(self):
        for updates in ({'live_ads': True}, {'approved_ads_store_path': '/data/ads.sqlite3'},
                        {'live_ads': True, 'production_billing': True,
                         'approved_ads_store_path': '/data/ads.sqlite3', 'ads_runtime': 'cloud-run'}):
            with self.assertRaises(ConfigurationError):
                replace(self.config, **updates).validate()
        config = replace(self.config, live_ads=True, production_billing=True,
                         approved_ads_store_path='/data/ads.sqlite3', ads_runtime='single-durable-host')
        with self.assertRaises(ConfigurationError): config.validate()
        for name in ('live_ads', 'production_billing'):
            self.rights['gates'][name]['enabled'] = True
        self.path.write_text(json.dumps(self.rights))
        config.validate()
        calls = []
        class Service:
            def event(self, raw): calls.append(raw); return {'status': 'accepted'}
        gated = RightsGatedAds(Service(), config)
        self.assertEqual('accepted', gated.event({'fixture': True})['status'])
        self.rights['gates']['live_ads']['enabled'] = False
        self.path.write_text(json.dumps(self.rights))
        with self.assertRaises(ConfigurationError): gated.event({'fixture': False})
        self.assertEqual([{'fixture': True}], calls)

    def test_organic_factory_never_opens_ads_when_disabled(self):
        class Ledger:
            def __init__(self, **kw): pass
            def snapshot(self): return {'global_cap_micros': 10000, 'unit_cost_micros': 5000,
                'approval_reference': 'fixture-only', 'profile': 'approved-production', 'environment': 'production'}
        calls = []
        app = create_search_application(self.config, ledger_factory=Ledger,
            secret_loader=lambda _: 'fixture-token-only', ads_factory=lambda path: calls.append(path))
        self.assertIsNone(app.ads)
        self.assertEqual([], calls)

    def _organic_fixtures(self):
        calls = {'reservations': [], 'completed': [], 'metrics': {}, 'transports': 0}

        class Ledger:
            def __init__(self, **kwargs): pass
            def snapshot(self):
                return {'global_cap_micros': 10000, 'unit_cost_micros': 5000,
                    'approval_reference': 'fixture-only', 'profile': 'approved-production', 'environment': 'production'}
            def reserve(self, kind):
                calls['reservations'].append(kind)
                return len(calls['reservations'])
            def complete(self, reservation, **kwargs):
                calls['completed'].append(kwargs)
            def record_search_event(self, name):
                calls['metrics'][name] = calls['metrics'].get(name, 0) + 1
            def search_metrics(self):
                return dict(calls['metrics'], durable=True, environment='production')

        class Transport:
            def request(self, kind, params, key):
                calls['transports'] += 1
                return FetchResult(200, {}, json.dumps({'query': {'more_results_available': False},
                    'web': {'results': [{'title': 'Fixture Python tools', 'url': 'https://docs.python.org/3/',
                                        'description': 'Synthetic runtime acceptance result'}]}}).encode())
        return calls, dict(ledger_factory=Ledger, secret_loader=lambda _: 'fixture-token-only', transport=Transport())

    def _live_ads_config(self):
        for gate in ('live_ads', 'production_billing'):
            self.rights['gates'][gate]['enabled'] = True
        self.path.write_text(json.dumps(self.rights))
        return replace(self.config, live_ads=True, production_billing=True,
                       approved_ads_store_path='/data/fixture-ads.sqlite3', ads_runtime='single-durable-host')

    def _wsgi_request(self, app, path='/v1/search', raw=None):
        body = json.dumps({'query': 'python'} if raw is None else raw).encode()
        reply = []
        result = app({'REQUEST_METHOD': 'POST', 'PATH_INFO': path, 'QUERY_STRING': '',
            'HTTP_HOST': 'gateway.wingman.org', 'wsgi.url_scheme': 'https',
            'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(body)),
            'wsgi.input': io.BytesIO(body)}, lambda status, headers: reply.append(status))
        return reply[0], json.loads(b''.join(result))

    def test_ad_rights_withdrawal_blocks_all_ads_but_preserves_organic_search(self):
        for gate in ('live_ads', 'production_billing'):
            with self.subTest(gate=gate):
                config = self._live_ads_config()
                calls, fixtures = self._organic_fixtures()
                ad_calls = []

                class Ads:
                    def issue_context(self, **kwargs): ad_calls.append('context'); return None
                    def decision(self, raw): ad_calls.append('decision'); return {}
                    def event(self, raw): ad_calls.append('event'); return {}
                    def asset(self, entity): ad_calls.append('asset'); return b'', 'image/png'

                application = create_search_application(config, ads_factory=lambda _: Ads(), **fixtures)
                http = SearchWSGI(application, config)
                self.rights['gates'][gate]['enabled'] = False
                self.path.write_text(json.dumps(self.rights))
                operations = (lambda: application.ads.issue_context(intent='office'),
                              lambda: application.ads.decision({}), lambda: application.ads.event({}),
                              lambda: application.ads.asset('0' * 64))
                for operation in operations:
                    with self.assertRaises(ConfigurationError): operation()
                self.assertEqual([], ad_calls)
                status, dto = self._wsgi_request(http)
                self.assertTrue(status.startswith('200'))
                self.assertEqual(1, len(dto['results']))
                self.assertEqual(['web'], calls['reservations'])
                self.assertEqual(1, calls['transports'])
                self.assertNotIn('adContext', dto)

    def test_closed_ad_store_does_not_abort_organic_factory_or_enable_events(self):
        config = self._live_ads_config()
        calls, fixtures = self._organic_fixtures()

        def unavailable(_):
            raise OSError('synthetic unavailable finance store')

        application = create_search_application(config, ads_factory=unavailable, **fixtures)
        self.assertIsNone(application.ads)
        self.assertTrue(application.ads_unavailable)
        http = SearchWSGI(application, config)
        self.assertTrue(self._wsgi_request(http)[0].startswith('200'))
        status, decision = self._wsgi_request(http, '/v1/ads/decision', {})
        self.assertTrue(status.startswith('200'))
        self.assertEqual('no-fill', decision['status'])
        _, event = self._wsgi_request(http, '/v1/ads/event', {})
        self.assertEqual('rejected', event['status'])
        self.assertFalse(event['billable'])
        self.assertEqual(0, event['chargedMicros'])
        self.assertEqual(1, calls['transports'])

    def test_revoked_ads_at_startup_do_not_open_store_or_require_full_config_gate(self):
        config = self._live_ads_config()
        self.rights['gates']['live_ads']['enabled'] = False
        self.path.write_text(json.dumps(self.rights))
        path = Path(self.temp.name) / 'config.json'
        from dataclasses import asdict
        path.write_text(json.dumps(asdict(config)))
        with self.assertRaises(ConfigurationError): read_config(path)
        scoped = read_config(path, required_gates={'live_search'})
        calls, fixtures = self._organic_fixtures()
        opened = []
        application = create_search_application(scoped, ads_factory=lambda p: opened.append(p), **fixtures)
        self.assertEqual([], opened)
        self.assertIsNone(application.ads)
        self.assertTrue(application.ads_unavailable)
        http = SearchWSGI(application, scoped)
        self.assertTrue(self._wsgi_request(http)[0].startswith('200'))
        self.assertEqual(1, calls['transports'])
        self.rights['gates']['live_search']['enabled'] = False
        self.path.write_text(json.dumps(self.rights))
        self.assertTrue(self._wsgi_request(http)[0].startswith('503'))
        with self.assertRaises(ConfigurationError):
            application.provider.before_request()
        self.assertEqual(1, calls['transports'])


if __name__ == '__main__': unittest.main()
