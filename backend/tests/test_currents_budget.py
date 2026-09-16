import json
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from wingman_content.currents_budget import (BudgetError, LocalLedger, GCSLedger,
    QUOTA_RESERVE, retry_time, stamp)

NOW = datetime(2026, 9, 16, tzinfo=timezone.utc)


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'operations' / 'currents.sqlite3'
        self.ledger = LocalLedger(self.path)
        self.ledger.initialize(NOW)

    def tearDown(self):
        self.temp.cleanup()

    def reserve(self, job='latest:general', now=NOW, **kwargs):
        return self.ledger.reserve(job, '/v2/latest-news', {'category': 'general'}, now,
                                   next_due=now + timedelta(hours=2), spacing_seconds=0, **kwargs)

    def test_all_150_slots_are_durable_and_never_refunded(self):
        for index in range(150):
            reserved = self.reserve('test:%d' % index)
            self.ledger.finish(reserved, NOW, error='transport-error')
        self.ledger = LocalLedger(self.path)
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 150)
        with self.assertRaisesRegex(BudgetError, 'local-budget-exhausted'):
            self.reserve('one-too-many')
        with self.assertRaisesRegex(BudgetError, 'ledger-already-exists'):
            self.ledger.initialize(NOW)

    def test_concurrent_independent_clients_reserve_only_one_lease(self):
        barrier = threading.Barrier(20)
        def reserve(index):
            barrier.wait()
            try:
                return LocalLedger(self.path).reserve('job:%d' % index, '/v2/latest-news', {}, NOW,
                    next_due=NOW + timedelta(hours=2), spacing_seconds=0)
            except BudgetError as exc:
                return exc.reason
        with ThreadPoolExecutor(max_workers=20) as pool:
            values = list(pool.map(reserve, range(20)))
        self.assertEqual(sum(isinstance(value, dict) for value in values), 1)
        self.assertEqual(values.count('lease-busy'), 19)
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 1)

    def test_crash_restart_deduplicates_slot_and_fences_old_worker(self):
        first = self.reserve()
        self.ledger = LocalLedger(self.path)
        later = NOW + timedelta(seconds=61)
        with self.assertRaisesRegex(BudgetError, 'not-due'):
            self.reserve(now=later)
        second = self.reserve('latest:sport', later)
        with self.assertRaisesRegex(BudgetError, 'lease-lost'):
            self.ledger.finish(first, later, status=200)
        self.ledger.finish(second, later, status=200)
        state = self.ledger.diagnostics(later)
        self.assertEqual(state['attempts'], 2)
        self.assertEqual(state['recentAttempts'][0]['outcome'], 'uncertain')

    def test_missing_and_corrupt_ledgers_fail_closed(self):
        with self.assertRaisesRegex(BudgetError, 'ledger-unavailable'):
            LocalLedger(Path(self.temp.name) / 'missing').diagnostics(NOW)
        self.path.write_bytes(b'corrupted database')
        with self.assertRaisesRegex(BudgetError, 'ledger-unavailable'):
            self.reserve()

    def test_corrupt_schema_fails_closed(self):
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE ledger SET state='{}'")
        with self.assertRaisesRegex(BudgetError, 'ledger-corrupt'):
            self.reserve()

    def test_utc_rollover_resets_only_daily_counters(self):
        reserved = self.reserve()
        self.ledger.finish(reserved, NOW, status=400)
        next_day = NOW + timedelta(days=1)
        state = self.ledger.diagnostics(next_day)
        self.assertEqual(state['attempts'], 0)
        self.assertTrue(state['jobs']['latest:general']['held'])
        self.assertEqual(state['history'][-1]['attempts'], 1)
        with self.assertRaisesRegex(BudgetError, 'clock-regressed'):
            self.ledger.diagnostics(NOW)

    def test_headers_lower_effective_cap_and_preserve_unknown_usage_reserve(self):
        reserved = self.reserve()
        self.ledger.finish(reserved, NOW, status=200,
            headers={'X-RateLimit-Limit': '100', 'x-RATELIMIT-remaining': '8'})
        state = self.ledger.diagnostics(NOW)
        self.assertEqual(state['attempts'], 1)
        self.assertEqual(state['providerRemaining'], 8)
        self.assertEqual(state['effectiveCap'], 4)
        for index in range(3):
            reserved = self.reserve('extra:%d' % index)
            self.ledger.finish(reserved, NOW, status=200)
        with self.assertRaisesRegex(BudgetError, 'local-budget-exhausted'):
            self.reserve('extra:4')
        rolled = self.ledger.diagnostics(NOW + timedelta(days=1))
        self.assertEqual(rolled['effectiveCap'], 100 - QUOTA_RESERVE)

    def test_high_plan_never_increases_150_cap(self):
        reserved = self.reserve()
        self.ledger.finish(reserved, NOW, status=200,
            headers={'X-RateLimit-Limit': '100000', 'X-RateLimit-Remaining': '99999'})
        self.assertEqual(self.ledger.diagnostics(NOW)['effectiveCap'], 150)

    def test_429_respects_retry_after_and_daily_exhaustion(self):
        reserved = self.reserve()
        self.ledger.finish(reserved, NOW, status=429,
            headers={'Retry-After': '900', 'X-RateLimit-Remaining': '0'})
        self.assertEqual(self.ledger.diagnostics(NOW)['pauseUntil'], stamp(NOW + timedelta(days=1)))
        with self.assertRaisesRegex(BudgetError, 'provider-wait'):
            self.reserve('other', NOW + timedelta(minutes=30))

    def test_retry_after_http_date_and_auth_pause_survive_restart(self):
        self.assertEqual(retry_time('Wed, 16 Sep 2026 01:00:00 GMT', NOW), NOW + timedelta(hours=1))
        reserved = self.reserve()
        self.ledger.finish(reserved, NOW, status=403)
        with self.assertRaisesRegex(BudgetError, 'authentication-paused'):
            LocalLedger(self.path).reserve('new', '/v2/latest-news', {}, NOW + timedelta(days=1),
                next_due=NOW + timedelta(days=2))

    def test_supplement_cap_and_headroom(self):
        for index in range(12):
            reserved = self.reserve('supplement:%d' % index, supplement=True)
            self.ledger.finish(reserved, NOW, status=200)
        with self.assertRaisesRegex(BudgetError, 'supplement-budget-reserve'):
            self.reserve('supplement:13', supplement=True)
        self.assertEqual(self.ledger.diagnostics(NOW)['attempts'], 12)

    def test_expired_fence_cannot_commit_even_without_successor(self):
        reservation = self.reserve()
        with self.assertRaisesRegex(BudgetError, 'lease-lost'):
            self.ledger.finish(reservation, NOW + timedelta(seconds=61), status=200)
        self.assertEqual(self.ledger.diagnostics(NOW)['recentAttempts'][0]['outcome'], 'uncertain')

    def test_inflight_midnight_rollover_keeps_old_attempt_and_discards_old_headers(self):
        when = NOW + timedelta(hours=23, minutes=59, seconds=59)
        reservation = self.reserve(now=when)
        self.ledger.finish(reservation, when + timedelta(seconds=2), status=200,
                           headers={'X-RateLimit-Remaining': '0'})
        state = self.ledger.diagnostics(NOW + timedelta(days=1, seconds=2))
        self.assertEqual(state['attempts'], 0)
        self.assertEqual(state['history'][-1]['attempts'], 1)
        self.assertIsNone(state['providerRemaining'])


class Conflict(Exception):
    code = 412


class FakeBucket:
    def __init__(self):
        self.lock = threading.Lock()
        self.value = None
        self.generation = 0
        self.conflicts = 0

    def bucket(self, name):
        return self

    def blob(self, name):
        parent = self
        class Blob:
            def reload(self, **kwargs):
                with parent.lock:
                    self.generation = parent.generation
                    self.size = len(parent.value or '')
            def download_as_bytes(self, if_generation_match, **kwargs):
                with parent.lock:
                    if parent.generation != if_generation_match:
                        raise Conflict()
                    return parent.value
            def upload_from_string(self, value, if_generation_match, **kwargs):
                with parent.lock:
                    if parent.conflicts:
                        parent.conflicts -= 1
                        raise Conflict()
                    if parent.generation != if_generation_match:
                        raise Conflict()
                    parent.value = value.encode()
                    parent.generation += 1
        return Blob()


class GCSLedgerTests(unittest.TestCase):
    def test_cas_conflicts_repeat_only_pure_mutation_and_do_not_reset(self):
        bucket = FakeBucket()
        ledger = GCSLedger('private', 'explicit-project', client=bucket)
        ledger.initialize(NOW)
        bucket.conflicts = 3
        reserved = ledger.reserve('latest:general', '/v2/latest-news', {}, NOW,
                                  next_due=NOW + timedelta(hours=2))
        self.assertEqual(ledger.diagnostics(NOW)['attempts'], 1)
        self.assertEqual(reserved['fence'], 1)
        with self.assertRaisesRegex(BudgetError, 'ledger-already-exists'):
            ledger.initialize(NOW)

    def test_multiple_instances_share_cap_and_lease(self):
        bucket = FakeBucket()
        first = GCSLedger('private', 'explicit-project', client=bucket)
        second = GCSLedger('private', 'explicit-project', client=bucket)
        first.initialize(NOW)
        first.reserve('latest:general', '/v2/latest-news', {}, NOW, next_due=NOW + timedelta(hours=2))
        with self.assertRaisesRegex(BudgetError, 'lease-busy'):
            second.reserve('latest:sport', '/v2/latest-news', {}, NOW, next_due=NOW + timedelta(hours=2))
        self.assertEqual(second.diagnostics(NOW)['attempts'], 1)


if __name__ == '__main__':
    unittest.main()
