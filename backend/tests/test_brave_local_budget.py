"""Synthetic local evaluation accounting; no real grant, key or network I/O."""
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from wingman_search.budget import BudgetError, BudgetLedger, rate_windows
from wingman_search.local_budget import (GRANT_ID, LIFETIME_MICROS, LocalEvaluationLedger,
                                        default_local_ledger_path)

REPO = Path(__file__).resolve().parents[2]
EPOCH = int(datetime(2026, 9, 26, tzinfo=timezone.utc).timestamp()) * 1_000_000


def process_attempt(args):
    path, now = args
    try:
        ledger = LocalEvaluationLedger(Path(path), actor='automated', clock=lambda: now)
        token = ledger.reserve('web')
        ledger.complete(token, status_class='success', http_status=200)
        return 'reserved'
    except BudgetError as exc:
        return exc.code


class LocalBudgetTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path(tempfile.mkdtemp(prefix='brave-local-grant-', dir=REPO / 'work'))
        self.path = self.directory / 'grant.sqlite3'
        self.old_path = self.directory / 'brave_budget.sqlite3'
        self.now = EPOCH

    def tearDown(self):
        shutil.rmtree(self.directory)

    def clock(self):
        return self.now

    def initialize(self, actor='automated', **kwargs):
        return LocalEvaluationLedger.initialize(self.path, actor=actor, clock=self.clock, **kwargs)

    def open(self, actor='automated'):
        return LocalEvaluationLedger(self.path, actor=actor, clock=self.clock)

    def spend(self, ledger, kind='web', status='success', http=200):
        token = ledger.reserve(kind)
        ledger.complete(token, status_class=status, http_status=http)
        self.now += 2_000_000
        return token

    def test_explicit_initialization_idempotent_fixed_seven_days(self):
        with self.assertRaises(BudgetError):
            self.open()
        self.assertFalse(self.path.exists())
        ledger = self.initialize()
        self.spend(ledger)
        self.now += 100_000_000
        state = self.initialize(actor='manual').snapshot()
        self.assertEqual(state['grant_id'], GRANT_ID)
        self.assertEqual(state['created_utc_micros'], EPOCH)
        self.assertEqual(state['expires_utc_micros'], EPOCH + LIFETIME_MICROS)
        self.assertEqual(state['attempts'], 1)
        self.assertEqual(state['remaining_attempts'], 99)
        self.assertEqual(state['remaining_automated_attempts'], 19)
        self.assertEqual(state['remaining_micros'], 495_000)
        self.assertEqual(state['endpoint_outcomes']['web']['latest_schema_reserved_at'], EPOCH)
        self.assertIsNone(state['endpoint_outcomes']['news']['latest_schema_reserved_at'])
        self.assertIsNone(state['actual_reconciled_micros'])
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(ledger.marker.stat().st_mode & 0o777, 0o600)

    def test_old_smoke_consolidates_and_cannot_spend_unused_allowance(self):
        old = BudgetLedger.initialize_smoke(self.old_path, clock=self.clock)
        reservation = self.spend(old)
        marker = old.marker.read_text()
        ledger = self.initialize()
        state = ledger.snapshot()
        self.assertEqual(state['old_smoke_attempts'], 1)
        self.assertEqual(state['attempts'], 1)
        self.assertEqual(state['automated_attempts'], 1)
        self.assertEqual(state['remaining_attempts'], 99)
        self.assertEqual(old.marker.read_text(), marker)
        with self.assertRaisesRegex(BudgetError, 'operator_intervention_required'):
            old.reserve('news')
        with self.assertRaises(BudgetError):
            BudgetLedger.initialize_smoke(self.old_path, clock=self.clock)
        old.reconcile(reservation.id, 5000)
        self.assertEqual(ledger.snapshot()['reconciled_billed_micros'], 5000)
        self.spend(ledger, 'news')
        self.assertEqual(ledger.snapshot()['attempts'], 2)

    def test_new_grant_creates_retired_zero_attempt_smoke_tombstone(self):
        self.initialize()
        old = BudgetLedger(self.old_path, clock=self.clock)
        self.assertEqual(old.snapshot()['attempts'], 0)
        self.assertTrue(old.snapshot()['halted'])
        with self.assertRaises(BudgetError):
            old.reserve('web')

    def test_no_second_filename_or_deleted_pair_can_replenish_same_grant(self):
        ledger = self.initialize()
        self.spend(ledger)
        with self.assertRaisesRegex(BudgetError, 'existing_local_grant'):
            LocalEvaluationLedger.initialize(self.directory / 'other.sqlite3', clock=self.clock)
        self.path.unlink()
        with self.assertRaises(BudgetError):
            self.initialize()
        ledger.marker.unlink()
        with self.assertRaisesRegex(BudgetError, 'existing_local_grant'):
            self.initialize()
        self.assertFalse(self.path.exists())

    def test_missing_corrupt_unsafe_or_reactivated_legacy_fails_closed(self):
        ledger = self.initialize()
        old_marker = self.old_path.with_name(self.old_path.name + '.initialized')
        original = old_marker.read_text()
        old_marker.write_text('wrong-identity')
        with self.assertRaises(BudgetError):
            ledger.reserve('web')
        old_marker.write_text(original)
        with sqlite3.connect(self.old_path) as db:
            db.execute('UPDATE state SET halted=0')
        with self.assertRaisesRegex(BudgetError, 'legacy_accounting_fence_broken'):
            ledger.reserve('web')
        with sqlite3.connect(self.old_path) as db:
            db.execute('UPDATE state SET halted=1')
        self.path.chmod(0o644)
        with self.assertRaises(BudgetError):
            self.open()
        self.path.chmod(0o600)
        self.path.write_bytes(b'corrupt')
        with self.assertRaises(BudgetError):
            self.open()
        with self.assertRaises(BudgetError):
            self.initialize()

    def test_legacy_missing_pair_or_pending_does_not_initialize_new_grant(self):
        old = BudgetLedger.initialize_smoke(self.old_path, clock=self.clock)
        token = old.reserve('web')
        with self.assertRaisesRegex(BudgetError, 'legacy_attempt_unresolved'):
            self.initialize()
        self.assertFalse(self.path.exists())
        old.complete(token, status_class='transport_error')
        old.marker.unlink()
        with self.assertRaises(BudgetError):
            self.initialize()
        self.assertFalse(self.path.exists())

    def test_automated_twenty_is_inside_hundred_and_manual_cannot_refill(self):
        ledger = self.initialize()
        for _ in range(20):
            self.spend(ledger)
        with self.assertRaisesRegex(BudgetError, 'automated_attempt_budget_exhausted'):
            self.open().reserve('news')
        manual = self.open(actor='manual')
        for _ in range(80):
            self.spend(manual, 'news')
        state = manual.snapshot()
        self.assertEqual((state['attempts'], state['automated_attempts'], state['manual_attempts']), (100, 20, 80))
        self.assertEqual(state['conservative_reserved_micros'], 500_000)
        self.assertEqual(state['remaining_attempts'], 0)
        with self.assertRaisesRegex(BudgetError, 'attempt_budget_exhausted'):
            self.initialize(actor='manual').reserve('news')
        self.assertFalse(state['billing_reconciliation_complete'])

    def test_reconciled_higher_charge_restricts_dollar_limit_without_refund(self):
        ledger = self.initialize()
        token = self.spend(ledger)
        ledger.reconcile(token.id, 496_000)
        self.assertEqual(ledger.snapshot()['remaining_micros'], 4000)
        self.assertEqual(ledger.snapshot()['conservative_reserved_micros'], 5000)
        with self.assertRaisesRegex(BudgetError, 'attempt_budget_exhausted'):
            ledger.reserve('news')
        with self.assertRaises(BudgetError):
            ledger.reconcile(token.id, 0)

    def test_expiry_and_clock_rollback_never_reset(self):
        ledger = self.initialize()
        self.now = EPOCH + LIFETIME_MICROS
        self.assertTrue(ledger.snapshot()['expired'])
        with self.assertRaisesRegex(BudgetError, 'local_evaluation_expired'):
            ledger.reserve('web')
        self.assertEqual(self.initialize().snapshot()['expires_utc_micros'], self.now)
        self.now = EPOCH - 1
        with self.assertRaisesRegex(BudgetError, 'clock_moved_backwards'):
            ledger.reserve('web')

    def test_all_pause_causes_require_matching_offline_correction_without_reset(self):
        ledger = self.initialize()
        for status, http, reason, correction in [
            ('auth_error', 401, 'authentication', 'credential-updated'),
            ('auth_error', 402, 'account-permission', 'account-corrected'),
            ('auth_error', 403, 'account-permission', 'account-corrected'),
            ('http_error', 400, 'request-validation', 'request-corrected'),
            ('http_error', 422, 'request-validation', 'request-corrected'),
            ('malformed_response', 200, 'response-schema', 'schema-corrected'),
        ]:
            self.spend(ledger, status=status, http=http)
            before = ledger.snapshot()
            self.assertEqual(before['pause_reason'], reason)
            with self.assertRaises(BudgetError):
                self.open().reserve('news')
            with self.assertRaisesRegex(BudgetError, 'matching_offline_correction_required'):
                ledger.resume(correction='retry')
            after = ledger.resume(correction=correction)
            self.assertEqual(after['attempts'], before['attempts'])
            self.assertEqual(after['expires_utc_micros'], before['expires_utc_micros'])
            self.assertEqual(after['conservative_reserved_micros'], before['conservative_reserved_micros'])
        state = ledger.snapshot()
        self.assertEqual(state['confirmed_successes'], 1)
        self.assertEqual(state['schema_successes'], 0)
        self.assertEqual(state['estimated_success_cost_micros'], 5000)
        self.assertIsNone(state['endpoint_outcomes']['web']['latest_schema_reserved_at'])

    def test_transport_unknown_and_abandoned_reservation_remain_charged(self):
        ledger = self.initialize()
        self.spend(ledger, status='transport_error', http=None)
        token = ledger.reserve('news')
        self.now += 5_000_000
        self.assertEqual(self.open().snapshot()['pause_reason'], 'previous-attempt-unresolved')
        with self.assertRaisesRegex(BudgetError, 'previous_attempt_unresolved'):
            self.open().reserve('web')
        ledger.resume(correction='transport-reviewed')
        state = ledger.snapshot()
        self.assertEqual(state['attempts'], 2)
        self.assertEqual(state['unknown_outcomes'], 2)
        self.assertEqual(state['unknown_reserved_micros'], 10000)
        self.assertEqual(state['confirmed_successes'], 0)
        with self.assertRaisesRegex(BudgetError, 'invalid_or_completed_reservation'):
            ledger.complete(token, status_class='success', http_status=200)

    def test_pacing_and_all_provider_windows_shared_between_actors(self):
        ledger = self.initialize()
        token = ledger.reserve('web')
        ledger.complete(token, status_class='success', http_status=200,
            rate_limit_headers={'X-RateLimit-Limit': '1, 3', 'X-RateLimit-Remaining': '0, 2',
                                'X-RateLimit-Reset': '5, 60', 'X-RateLimit-Policy': '1;w=5, 3;w=60'})
        self.now += 1_999_999
        with self.assertRaisesRegex(BudgetError, 'shared_backoff'):
            self.open(actor='manual').reserve('news')
        self.now += 1
        with self.assertRaisesRegex(BudgetError, 'provider_quota_exhausted'):
            self.open().reserve('news')
        self.now += 3_000_000
        self.spend(self.open(actor='manual'), 'news')
        self.spend(ledger)
        with self.assertRaisesRegex(BudgetError, 'provider_quota_exhausted'):
            ledger.reserve('news')

    def test_429_and_invalid_rate_metadata_pause_separately(self):
        ledger = self.initialize()
        token = ledger.reserve('web')
        ledger.complete(token, status_class='rate_limited', http_status=429, rate_limit_headers={'Retry-After': '30'})
        self.now += 3_000_000
        self.assertFalse(ledger.snapshot()['halted'])
        with self.assertRaisesRegex(BudgetError, 'shared_backoff'):
            ledger.reserve('web')
        self.now += 30_000_000
        token = ledger.reserve('news')
        ledger.complete(token, status_class='success', http_status=200, rate_limit_headers={'X-RateLimit-Limit': 'secret-or-query-is-discarded'})
        self.assertEqual(ledger.snapshot()['pause_reason'], 'rate-metadata')
        self.now += 2_000_000
        ledger.resume(correction='rate-metadata-corrected')
        self.spend(ledger)
        self.assertNotIn(b'secret-or-query-is-discarded', self.path.read_bytes())

    def test_documented_unlimited_monthly_quota_preserves_finite_pacing(self):
        headers = {'X-RateLimit-Limit': '1, 0', 'X-RateLimit-Remaining': '0, 0',
                   'X-RateLimit-Reset': '1, 2592000', 'X-RateLimit-Policy': '1;w=1, 0;w=2592000'}
        windows, _ = rate_windows(headers, self.now)
        self.assertEqual(len(windows), 1)
        self.assertEqual(windows[0]['remaining'], 0)
        ledger = self.initialize()
        token = ledger.reserve('web')
        ledger.complete(token, status_class='success', http_status=200, rate_limit_headers=headers)
        self.now += 1_000_000
        with self.assertRaisesRegex(BudgetError, 'shared_backoff'):
            ledger.reserve('news')
        self.now += 1_000_000
        self.spend(ledger, 'news')
        self.assertEqual(ledger.snapshot()['remaining_attempts'], 98)
        for policy in ('1;w=1, 0;w=2', None):
            ambiguous = dict(headers)
            if policy is None:
                del ambiguous['X-RateLimit-Policy']
            else:
                ambiguous['X-RateLimit-Policy'] = policy
            with self.assertRaisesRegex(BudgetError, 'invalid_rate_metadata'):
                rate_windows(ambiguous, self.now)
        with self.assertRaisesRegex(BudgetError, 'invalid_rate_metadata'):
            rate_windows({'X-RateLimit-Limit': '0', 'X-RateLimit-Remaining': '0',
                          'X-RateLimit-Reset': '1', 'X-RateLimit-Policy': '0;w=2592000'}, self.now)

    def test_auth_and_bad_rate_metadata_require_both_offline_corrections(self):
        ledger = self.initialize()
        token = ledger.reserve('web')
        ledger.complete(token, status_class='auth_error', http_status=401,
                        rate_limit_headers={'X-RateLimit-Remaining': 'invalid'})
        self.now += 2_000_000
        self.assertEqual(ledger.snapshot()['pause_reason'], 'authentication')
        ledger.resume(correction='credential-updated')
        self.assertEqual(ledger.snapshot()['pause_reason'], 'rate-metadata')
        with self.assertRaisesRegex(BudgetError, 'local_evaluation_paused_rate-metadata'):
            ledger.reserve('news')
        ledger.resume(correction='rate-metadata-corrected')
        self.assertEqual(ledger.snapshot()['attempts'], 1)
        self.spend(ledger, 'news')

    def test_separate_processes_cannot_race_or_spend_before_pacing(self):
        self.initialize()
        with ProcessPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(process_attempt, [(str(self.path), self.now)] * 8))
        self.assertEqual(results.count('reserved'), 1)
        self.assertEqual(self.open().snapshot()['attempts'], 1)

    def test_init_commit_failure_preserves_marker_and_atomic_old_retirement(self):
        old = BudgetLedger.initialize_smoke(self.old_path, clock=self.clock)
        real_connect = sqlite3.connect
        class FailCommit:
            def __init__(self, db): object.__setattr__(self, 'db', db)
            def __getattr__(self, name): return getattr(self.db, name)
            def __setattr__(self, name, value): setattr(self.db, name, value)
            def commit(self): raise sqlite3.OperationalError('synthetic commit failure')
        def connect(path, *args, **kwargs):
            db = real_connect(path, *args, **kwargs)
            return FailCommit(db) if str(path).startswith(self.path.as_uri()) else db
        with patch('wingman_search.local_budget.sqlite3.connect', side_effect=connect):
            with self.assertRaisesRegex(BudgetError, 'initialization_incomplete'):
                self.initialize()
        self.assertFalse(old.snapshot()['halted'])
        self.assertTrue(self.path.with_name(self.path.name + '.initialized').exists())
        with self.assertRaises(BudgetError):
            self.initialize()

    def test_owner_only_symlinks_invalid_actor_price_and_production_refused(self):
        with self.assertRaises(BudgetError):
            self.initialize(actor='consumer-supplied')
        with self.assertRaisesRegex(BudgetError, 'higher_unit_price'):
            self.initialize(unit_cost_micros=5001)
        with self.assertRaisesRegex(BudgetError, 'production_requires_shared_ledger'):
            self.initialize(environment='production')
        ledger = self.initialize()
        renamed = self.directory / 'saved.sqlite3'
        self.path.rename(renamed)
        self.path.symlink_to(renamed)
        with self.assertRaises(BudgetError):
            self.open()
        self.assertEqual(ledger.marker.stat().st_mode & 0o777, 0o600)

    def test_path_is_shared_across_git_worktrees(self):
        repo = self.directory / 'repository'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        'commit', '--allow-empty', '-qm', 'fixture'], check=True, capture_output=True)
        other = self.directory / 'worktree'
        subprocess.run(['git', '-C', str(repo), 'worktree', 'add', '-q', '--detach', str(other)], check=True, capture_output=True)
        self.assertEqual(default_local_ledger_path(repo).resolve(), default_local_ledger_path(other).resolve())

    def test_durable_schema_contains_no_consumer_data_or_response_columns(self):
        ledger = self.initialize()
        self.spend(ledger)
        with sqlite3.connect(self.path) as db:
            tables = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
            columns = {r[1] for table in tables for r in db.execute(f'PRAGMA table_info({table})')}
        self.assertFalse(columns & {'query', 'url', 'body', 'key', 'token', 'client_id', 'ip', 'locale', 'result'})
        self.assertEqual(set(tables), {'state', 'attempts', 'corrections'})


if __name__ == '__main__':
    unittest.main()
