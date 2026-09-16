import copy
import json
import tempfile
import unittest
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

from wingman_content.config import load_config
from wingman_content.currents import (BudgetGateway, CurrentsProvider, CATEGORIES,
    DERIVED_QUERIES, _CurrentsTransport, interval)
from wingman_content.currents_budget import BudgetError, LocalLedger, stamp, moment
from wingman_content.fetch import FetchResult
from wingman_content.normalize import parse_currents_news, currents_topics

NOW = datetime(2026, 9, 16, tzinfo=timezone.utc)
ROOT = Path(__file__).resolve().parents[2]
SOURCE = next(source for source in load_config(ROOT / 'backend/sources.json')['sources'] if source['id'] == 'currents')


class Allow:
    def allows(self, url):
        return True


def response(data=None, status=200, headers=None):
    return FetchResult(status, headers or {}, json.dumps(data if data is not None else {'status': 'ok', 'news': []}).encode())


def article(index=1, **values):
    result = {'id': str(index), 'title': 'Researchers investigate a new discovery',
        'description': 'A scientific study explains the evidence.', 'url': 'https://publisher.example/news/%s' % index,
        'language': 'en', 'category': ['science_technology'], 'published': '2026-09-16 00:00:00 +0000',
        'image': None, 'author': None}
    result.update(values)
    return result


class Transport:
    def __init__(self, values=None):
        self.calls = []
        self.values = values or []
    def request(self, path, params, authorization):
        self.calls.append((path, dict(params), authorization))
        if self.values:
            value = self.values.pop(0)
            if isinstance(value, Exception):
                raise value
            return value
        if path == '/v2/available/categories':
            return response({'status': 'ok', 'categories': list(CATEGORIES)})
        if path == '/v2/available/regions':
            return response({'status': 'ok', 'regions': {'United States': 'US'}})
        if path == '/v2/available/languages':
            return response({'status': 'ok', 'languages': {'English': 'en'}})
        return response()


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ledger = LocalLedger(Path(self.temp.name) / 'operations.sqlite3')
        self.ledger.initialize(NOW)
        self.transport = Transport()
        self.gateway = BudgetGateway(self.ledger, key='fixture-not-a-real-secret', transport=self.transport, spacing_seconds=0)
        self.provider = CurrentsProvider(Allow(), self.gateway)
    def tearDown(self):
        self.temp.cleanup()
    def ready(self):
        self.ledger.update(lambda state: state.update(authStatus='ok', authAttempted=True,
            metadata={key: {'values': values, 'fetchedAt': stamp(NOW), 'expiresAt': stamp(NOW + timedelta(days=7))}
                      for key, values in {'categories': list(CATEGORIES), 'regions': ['US'], 'languages': ['en']}.items()}))

    def test_setup_counts_auth_and_metadata_once_and_caches_seven_days(self):
        report = self.provider.setup(NOW)
        self.assertEqual([row['status'] for row in report], ['ok'] * 4)
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 4)
        self.provider.setup(NOW + timedelta(days=1))
        self.assertEqual(len(self.transport.calls), 4)
        self.provider.setup(NOW + timedelta(days=8))
        self.assertEqual(len(self.transport.calls), 7)
        self.assertEqual(sum(path == '/v1/auth' for path, _, _ in self.transport.calls), 1)

    def test_failed_key_pauses_and_deliberate_replacement_does_not_reset_budget(self):
        self.transport.values = [response(status=401)]
        self.provider.setup(NOW)
        self.provider.setup(NOW + timedelta(hours=1))
        self.assertEqual(len(self.transport.calls), 1)
        self.provider.setup(NOW + timedelta(hours=2), replace_credential=True)
        self.assertEqual(len(self.transport.calls), 5)
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 5)

    def test_setup_deferral_before_reservation_does_not_mark_key_checked_or_failed(self):
        held = self.ledger.reserve('latest:general', '/v2/latest-news', {}, NOW,
                                   next_due=NOW + timedelta(hours=2), spacing_seconds=0)
        report = self.provider.setup(NOW)
        self.assertEqual(report[0]['status'], 'lease-busy')
        state = self.ledger.diagnostics(NOW)
        self.assertFalse(state['authAttempted'])
        self.assertIsNone(state['authStatus'])
        self.assertIsNone(state['pauseReason'])
        self.ledger.finish(held, NOW, status=200)
        self.provider.setup(NOW)
        self.assertEqual(sum(path == '/v1/auth' for path, _, _ in self.transport.calls), 1)
        self.assertEqual(self.ledger.diagnostics(NOW)['authStatus'], 'ok')

    def test_setup_after_exhausted_day_can_resume_without_credential_replacement(self):
        self.ledger.update(lambda state: state.update(effectiveCap=0))
        self.assertEqual(self.provider.setup(NOW)[0]['status'], 'local-budget-exhausted')
        self.assertFalse(self.ledger.diagnostics(NOW)['authAttempted'])
        self.provider.setup(NOW + timedelta(days=1))
        self.assertEqual(sum(path == '/v1/auth' for path, _, _ in self.transport.calls), 1)
        self.assertEqual(self.ledger.diagnostics(NOW + timedelta(days=1))['attempts'], 4)

    def test_metadata_refresh_failure_keeps_validated_taxonomy(self):
        self.provider.setup(NOW)
        self.transport.values = [response(status=500)]
        report = self.provider.setup(NOW + timedelta(days=8))
        self.assertTrue(report[0]['lastKnownRetained'])
        self.assertEqual(set(self.ledger.diagnostics(NOW + timedelta(days=8))['metadata']['categories']['values']), set(CATEGORIES))

    def test_48_hours_base_is_104_each_day_and_supplements_at_most_12(self):
        self.ready()
        state = {}
        counts = defaultdict(Counter)
        for tick in range(96):
            now = NOW + timedelta(minutes=30 * tick)
            before = len(self.transport.calls)
            state = self.provider.refresh(SOURCE, state, now)
            calls = self.transport.calls[before:]
            self.assertLessEqual(len(calls), 4)
            for path, params, _ in calls:
                counts[now.date().isoformat()][path] += 1
                if path == '/v2/latest-news':
                    self.assertEqual(set(params), {'language', 'country', 'category', 'page_number', 'page_size'})
                    self.assertIn(params['category'], CATEGORIES)
                elif path == '/v2/search':
                    self.assertIn(params['query'], DERIVED_QUERIES.values())
                    self.assertNotIn('category', params)
                    self.assertNotIn('keywords', params)
                    self.assertEqual(moment(params['end_date']) - moment(params['start_date']), timedelta(days=7))
            self.assertLessEqual(self.ledger.diagnostics(now)['attempts'], 150)
        for day in counts.values():
            self.assertEqual(day['/v2/latest-news'], 104)
            self.assertLessEqual(day['/v2/search'], 12)
            self.assertLessEqual(sum(day.values()), 116)
        for category in CATEGORIES:
            count = sum(params.get('category') == category for path, params, _ in self.transport.calls)
            self.assertEqual(count, 24 if interval(category) == 7200 else 8)
        for query in DERIVED_QUERIES.values():
            times = [moment(params['end_date']) for path, params, _ in self.transport.calls
                     if path == '/v2/search' and params['query'] == query]
            self.assertTrue(all(right - left >= timedelta(hours=6) for left, right in zip(times, times[1:])))

    def test_duplicate_scheduler_ticks_and_500_client_reads_do_not_fetch(self):
        self.ready()
        state = self.provider.refresh(SOURCE, {}, NOW)
        before = len(self.transport.calls)
        state = self.provider.refresh(SOURCE, state, NOW)
        self.assertEqual(len(self.transport.calls), before)
        # The read-only service has no provider argument or ingestion callback.
        from wingman_content.provider import public_snapshot
        for _ in range(500):
            public_snapshot({'sources': [SOURCE]}, {'currents': state}, NOW)
        self.assertEqual(len(self.transport.calls), before)

    def test_bootstrap_16_categories_and_no_immediate_duplicate(self):
        self.ready()
        state = self.provider.bootstrap(SOURCE, {}, NOW + timedelta(hours=1, minutes=59))
        self.assertEqual(len(self.transport.calls), 16)
        self.assertEqual({params['category'] for _, params, _ in self.transport.calls}, set(CATEGORIES))
        self.assertTrue(all(moment(job['nextDue']) >= NOW + timedelta(hours=3, minutes=59)
                            for name, job in self.ledger.diagnostics(NOW)['jobs'].items() if name.startswith('latest:')))
        self.provider.bootstrap(SOURCE, state, NOW + timedelta(hours=2))
        self.assertEqual(len(self.transport.calls), 16)

    def test_outage_resumes_fairly_without_catchup_burst(self):
        self.ready()
        state = self.provider.refresh(SOURCE, {}, NOW)
        start = len(self.transport.calls)
        for tick in range(8):
            before = len(self.transport.calls)
            state = self.provider.refresh(SOURCE, state, NOW + timedelta(days=2, minutes=30 * tick))
            self.assertLessEqual(len(self.transport.calls) - before, 4)
        seen = {params['category'] for path, params, _ in self.transport.calls[start:] if path == '/v2/latest-news'}
        self.assertEqual(seen, set(CATEGORIES))

    def test_fixed_query_contract_rejects_legacy_categories_and_arbitrary_queries_before_reserve(self):
        base = {'language': 'en', 'country': 'US', 'page_number': 1, 'page_size': 20}
        for params in (dict(base, category='sports'), dict(base, category='food'),
                       dict(base, category='general', has_image=True), dict(base, category='general', apiKey='forbidden')):
            with self.assertRaises(BudgetError):
                self.gateway.request('/v2/latest-news', params, 'latest:general', NOW, next_due=NOW + timedelta(hours=2))
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 0)
        self.assertEqual(self.transport.calls, [])

    def test_error_envelopes_transport_and_empty_results_count_exactly_once(self):
        for index, value in enumerate([response({'status': 'error', 'message': 'secret response'}),
            RuntimeError('Authorization: Bearer fixture-not-a-real-secret'), response()]):
            self.transport.values = [value]
            try:
                result = self.gateway.request('/v2/latest-news', {'category': 'general', 'language': 'en',
                    'country': 'US', 'page_number': 1, 'page_size': 20}, 'case:%d' % index, NOW,
                    next_due=NOW + timedelta(hours=2))
                self.assertEqual(result.data['news'], [])
            except BudgetError as exc:
                self.assertNotIn('fixture-not-a-real-secret', str(exc))
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 3)
        self.assertNotIn('fixture-not-a-real-secret', json.dumps(self.ledger.diagnostics(NOW)))

    def test_400_holds_one_query_500_defers_and_401_pauses_provider(self):
        self.ready()
        self.transport.values = [response(status=400), response(status=500), response(status=401)]
        state = self.provider.refresh(SOURCE, {}, NOW)
        ledger = self.ledger.diagnostics(NOW)
        self.assertEqual(len(self.transport.calls), 3)
        self.assertEqual(ledger['pauseReason'], 'authentication')
        self.assertEqual(sum(bool(job.get('held')) for job in ledger['jobs'].values()), 1)
        self.assertTrue(any(job.get('failures') == 1 for job in ledger['jobs'].values()))
        self.provider.refresh(SOURCE, state, NOW + timedelta(hours=1))
        self.assertEqual(len(self.transport.calls), 3)

    def test_sufficient_derived_pool_skips_supplements(self):
        self.ready()
        items, _ = parse_currents_news([article(i, title='Recipes and cooking techniques', category=['lifestyle_leisure'])
                                      for i in range(5)], SOURCE, NOW, Allow())
        prior = {'currentsPools': {'seed': items}, 'items': items}
        self.provider.refresh(SOURCE, prior, NOW + timedelta(hours=5, minutes=30))
        self.assertFalse(any(params.get('query') == DERIVED_QUERIES['food'] for _, params, _ in self.transport.calls))

    def test_optional_values_and_all_category_mappings(self):
        for category in CATEGORIES:
            items, _ = parse_currents_news([article(category, image='null', description=None, author=None,
                                                   category=[category])], SOURCE, NOW, Allow(), category)
            self.assertEqual(len(items), 1)
            self.assertEqual(items[0]['providerId'], 'currents')
            self.assertEqual(items[0]['publisherName'], 'publisher.example')
            self.assertEqual(items[0]['publishedAt'], '2026-09-16T00:00:00Z')
            self.assertIsNone(items[0]['image'])
            self.assertEqual(items[0]['originalUrl'], 'https://publisher.example/news/%s' % category)
        self.assertNotIn('technology', currents_topics(['science_technology'], 'Scientific research study'))
        self.assertNotIn('food', currents_topics(['lifestyle_leisure'], 'People gather for community event'))

    def test_retention_does_not_slide_on_cached_reads_or_failures(self):
        self.ready()
        self.transport.values = [response({'status': 'ok', 'news': [article()]})]
        state = self.provider.refresh(SOURCE, {}, NOW)
        expiry = state['items'][0]['expiresAt']
        for minute in (1, 2, 3):
            state = self.provider.refresh(SOURCE, state, NOW + timedelta(minutes=minute))
            self.assertEqual(state['items'][0]['expiresAt'], expiry)
        self.gateway._key = None
        state = self.provider.refresh(SOURCE, state, NOW + timedelta(days=2))
        self.assertFalse(state.get('items'))

    def test_weekly_metadata_refresh_shares_four_attempt_tick_limit(self):
        self.ready()
        state = self.provider.refresh(SOURCE, {}, NOW)
        before = len(self.transport.calls)
        self.provider.refresh(SOURCE, state, NOW + timedelta(days=8))
        calls = self.transport.calls[before:]
        self.assertLessEqual(len(calls), 4)
        self.assertEqual(sum(path.startswith('/v2/available/') for path, _, _ in calls), 3)
        self.assertFalse(any(path == '/v1/auth' for path, _, _ in calls))

    def test_ledger_failure_preserves_eligible_cached_preview_without_network(self):
        self.ready()
        items, _ = parse_currents_news([article()], SOURCE, NOW, Allow())
        self.ledger.path.write_bytes(b'broken')
        state = self.provider.refresh(SOURCE, {'items': items, 'lastSuccessAt': stamp(NOW)}, NOW)
        self.assertEqual(len(state['items']), 1)
        self.assertEqual(self.transport.calls, [])
        self.assertEqual(state['error'], 'ledger-unavailable')

    def test_cache_headers_shorten_retention_and_no_store_removes_preview(self):
        self.ready()
        self.transport.values = [response({'status': 'ok', 'news': [article()]}, headers={'Cache-Control': 'max-age=60'})]
        state = self.provider.refresh(SOURCE, {}, NOW)
        self.assertLessEqual(moment(state['items'][0]['expiresAt']), NOW + timedelta(seconds=61))
        self.transport.values = [response({'status': 'ok', 'news': [article(2)]}, headers={'Cache-Control': 'private'})]
        state = self.provider.refresh(SOURCE, state, NOW + timedelta(minutes=30))
        self.assertEqual(state['items'], [])

    def test_writer_guard_stops_before_or_after_reservation(self):
        params = {'language': 'en', 'country': 'US', 'category': 'general', 'page_number': 1, 'page_size': 20}
        def reject():
            raise RuntimeError('writer-lease-lost')
        self.gateway.before_request = reject
        with self.assertRaisesRegex(RuntimeError, 'writer-lease-lost'):
            self.gateway.request('/v2/latest-news', params, 'latest:general', NOW, next_due=NOW + timedelta(hours=2))
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 0)
        checks = []
        def second_reject():
            checks.append(1)
            if len(checks) == 2:
                reject()
        self.gateway.before_request = second_reject
        with self.assertRaisesRegex(RuntimeError, 'writer-lease-lost'):
            self.gateway.request('/v2/latest-news', params, 'latest:general', NOW, next_due=NOW + timedelta(hours=2))
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 1)
        self.assertEqual(self.transport.calls, [])


class TransportSecurityTests(unittest.TestCase):
    def test_redirect_is_not_followed_and_bearer_never_appears_in_request_url(self):
        calls = []
        class Connection:
            sock = None
            def __init__(self, host, address, timeout):
                calls.append({'host': host})
            def request(self, method, path, headers):
                calls[-1].update(path=path, headers=headers)
            def getresponse(self):
                class Reply:
                    status = 302
                    def getheaders(self):
                        return [('Location', 'https://attacker.example/steal')]
                return Reply()
            def close(self):
                pass
        transport = _CurrentsTransport(resolver=lambda host, timeout: ['8.8.8.8'], connector=Connection)
        result = transport.request('/v1/auth', {}, 'Bearer test-marker')
        self.assertEqual(result.status, 302)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]['host'], 'api.currentsapi.services')
        self.assertNotIn('test-marker', calls[0]['path'])
        self.assertEqual(calls[0]['headers']['Authorization'], 'Bearer test-marker')

    def test_private_dns_prevents_transport(self):
        transport = _CurrentsTransport(resolver=lambda host, timeout: ['127.0.0.1'],
                                     connector=lambda *args: self.fail('must not connect'))
        with self.assertRaisesRegex(Exception, 'currents-transport-error'):
            transport.request('/v1/auth', {}, 'Bearer test-marker')


if __name__ == '__main__':
    unittest.main()
