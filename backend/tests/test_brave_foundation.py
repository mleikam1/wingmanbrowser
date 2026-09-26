"""Fixture-only foundation tests; these never contact a provider or read real keys."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from wingman_search.budget import BudgetError, BudgetLedger, default_ledger_path, rate_windows
from wingman_search.config import ConfigurationError, SearchConfig, load_rights, require_right, validate_production_url
from wingman_search.secrets import SecretError, default_secret_path, load_secret, secret_status, validate_key, write_secret

REPO = Path(__file__).absolute().parents[2]
EPOCH = int(datetime(2026, 9, 26, tzinfo=timezone.utc).timestamp()) * 1_000_000
FAKE_KEY = "fixture-only-not-a-provider-key"


class SecureTemporaryTest(unittest.TestCase):
    def setUp(self):
        work = REPO / "work"
        work.mkdir(exist_ok=True)
        self.directory = Path(tempfile.mkdtemp(prefix="brave-foundation-", dir=work))
        self.path = self.directory / "ledger.sqlite3"
        self.now = EPOCH

    def tearDown(self):
        shutil.rmtree(self.directory)

    def clock(self):
        return self.now

    def ledger(self):
        return BudgetLedger.initialize_smoke(self.path, clock=self.clock)


class BudgetTests(SecureTemporaryTest):
    def test_explicit_init_only_and_marker_prevents_replenishment(self):
        with self.assertRaises(BudgetError):
            BudgetLedger(self.path)
        self.assertFalse(self.path.exists())
        self.ledger()
        with self.assertRaises(BudgetError):
            self.ledger()
        self.path.unlink()
        with self.assertRaises(BudgetError):
            BudgetLedger(self.path)
        with self.assertRaises(BudgetError):
            self.ledger()
        self.assertFalse(self.path.exists())

    def test_success_budgets_are_fixed_separate_and_survive_restart(self):
        ledger = self.ledger()
        web = ledger.reserve("web")
        ledger.complete(web, status_class="success", http_status=200)
        self.now += 1_000_000
        restarted = BudgetLedger(self.path, clock=self.clock)
        with self.assertRaisesRegex(BudgetError, "attempt_budget_exhausted"):
            restarted.reserve("web")
        news = restarted.reserve("news")
        restarted.complete(news, status_class="success", http_status=200)
        self.now += 400 * 86_400_000_000
        with self.assertRaisesRegex(BudgetError, "attempt_budget_exhausted"):
            restarted.reserve("news")
        result = restarted.snapshot()
        self.assertEqual(result["attempts"], 2)
        self.assertEqual(result["conservative_reserved_micros"], 10_000)
        self.assertEqual(result["estimated_success_cost_micros"], 10_000)
        self.assertEqual(result["reconciled_billed_micros"], 0)
        self.assertEqual(result["reconciled_attempts"], 0)
        self.assertEqual(result["unknown_outcomes"], 0)
        self.assertFalse(result["billing_reconciliation_complete"])
        restarted.reconcile(web.id, 5000)
        self.assertEqual(restarted.snapshot()["reconciled_billed_requests"], 1)
        self.assertFalse(restarted.snapshot()["billing_reconciliation_complete"])
        restarted.reconcile(news.id, 0)
        self.assertTrue(restarted.snapshot()["billing_reconciliation_complete"])

    def test_first_failure_stops_smoke_and_unknown_is_not_confirmed_charge(self):
        ledger = self.ledger()
        attempt = ledger.reserve("web")
        ledger.complete(attempt, status_class="transport_error")
        self.now += 10_000_000
        with self.assertRaisesRegex(BudgetError, "operator_intervention_required"):
            BudgetLedger(self.path, clock=self.clock).reserve("news")
        report = ledger.snapshot()
        self.assertEqual(report["unknown_outcomes"], 1)
        self.assertEqual(report["unknown_reserved_micros"], 5_000)
        self.assertEqual(report["confirmed_successes"], 0)
        self.assertEqual(report["estimated_success_cost_micros"], 0)
        self.assertFalse(report["billing_reconciliation_complete"])
        ledger.reconcile(attempt.id, 0)
        self.assertEqual(ledger.snapshot()["conservative_reserved_micros"], 5_000)
        self.assertEqual(ledger.snapshot()["reconciled_attempts"], 1)
        self.assertEqual(ledger.snapshot()["reconciled_billed_requests"], 0)
        self.assertTrue(ledger.snapshot()["billing_reconciliation_complete"])

    def test_received_success_with_bad_schema_is_estimated_billed_and_stops(self):
        ledger = self.ledger()
        attempt = ledger.reserve("web")
        ledger.complete(attempt, status_class="malformed_response", http_status=200)
        report = ledger.snapshot()
        self.assertEqual(report["confirmed_successes"], 1)
        self.assertEqual(report["schema_successes"], 0)
        self.assertEqual(report["estimated_success_cost_micros"], 5_000)
        self.assertTrue(report["halted"])

    def test_auth_failure_never_loops(self):
        ledger = self.ledger()
        attempt = ledger.reserve("web")
        ledger.complete(attempt, status_class="auth_error", http_status=401)
        self.now += 100_000_000
        with self.assertRaisesRegex(BudgetError, "operator_intervention_required"):
            ledger.reserve("news")

    def test_interrupted_pending_dispatch_remains_reserved(self):
        self.ledger().reserve("web")
        self.now += 100_000_000
        restarted = BudgetLedger(self.path, clock=self.clock)
        with self.assertRaisesRegex(BudgetError, "previous_attempt_unresolved"):
            restarted.reserve("news")
        self.assertEqual(restarted.snapshot()["unknown_outcomes"], 1)

    def test_invalid_completion_does_not_destroy_reservation(self):
        ledger = self.ledger()
        attempt = ledger.reserve("web")
        with self.assertRaises(BudgetError):
            ledger.complete(attempt, status_class="success")
        self.assertEqual(ledger.snapshot()["unknown_outcomes"], 1)

    def test_qps_is_shared_across_endpoints(self):
        ledger = self.ledger()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200)
        with self.assertRaisesRegex(BudgetError, "shared_backoff"):
            BudgetLedger(self.path, clock=self.clock).reserve("news")
        self.now += 1_000_000
        ledger.reserve("news")

    def test_provider_all_windows_are_persisted_and_enforced(self):
        ledger = self.ledger()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200,
                        rate_limit_headers={"X-RateLimit-Limit": "1, 2", "X-RateLimit-Remaining": "0, 0",
                                            "X-RateLimit-Reset": "1, 60", "X-RateLimit-Policy": "1;w=1, 2;w=60"})
        self.now += 2_000_000
        with self.assertRaisesRegex(BudgetError, "provider_quota_exhausted"):
            BudgetLedger(self.path, clock=self.clock).reserve("news")
        self.now += 60_000_000
        ledger.reserve("news")

    def test_retry_after_date_and_seconds(self):
        _, numeric = rate_windows({"Retry-After": "30"}, EPOCH)
        _, date = rate_windows({"Retry-After": "Sat, 26 Sep 2026 00:00:30 GMT"}, EPOCH)
        self.assertEqual(numeric, EPOCH + 30_000_000)
        self.assertEqual(date, numeric)

    def test_invalid_rate_metadata_stops_safely(self):
        ledger = self.ledger()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200,
                        rate_limit_headers={"X-RateLimit-Limit": "many"})
        self.assertTrue(ledger.snapshot()["halted"])

    def test_production_sqlite_and_unclassified_calls_refused(self):
        with self.assertRaisesRegex(BudgetError, "production_requires_shared_ledger"):
            BudgetLedger(self.path, environment="production")
        ledger = self.ledger()
        for kind in ("images", "suggest", "answer", "https://example.com"):
            with self.assertRaisesRegex(BudgetError, "unclassified_endpoint"):
                ledger.reserve(kind)
        self.assertEqual(ledger.snapshot()["attempts"], 0)

    def test_corrupt_ledger_and_unsafe_permissions_refused(self):
        ledger = self.ledger()
        self.path.chmod(0o644)
        with self.assertRaises(BudgetError):
            ledger.reserve("web")
        self.path.chmod(0o600)
        self.path.write_bytes(b"corrupt-not-a-database")
        with self.assertRaises(BudgetError):
            BudgetLedger(self.path)

    def test_accounting_schema_has_no_consumer_data(self):
        ledger = self.ledger()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200)
        with sqlite3.connect(self.path) as db:
            columns = {row[1] for row in db.execute("PRAGMA table_info(attempts)")}
        self.assertEqual(columns, {"id", "endpoint", "environment", "date_bucket", "reserved_at",
                                   "reserved_cost", "status_class", "http_status", "reconciled_cost"})
        for forbidden in (b"query", b"referrer", b"client_ip", b"BRAVE_API_KEY", FAKE_KEY.encode()):
            self.assertNotIn(forbidden, self.path.read_bytes())

    def test_new_local_approval_caps_default_zero_and_never_refunded(self):
        ledger = BudgetLedger.initialize_approved(self.path, approval_reference="fixture-zero-budget",
                 global_cap_micros=0, endpoint_daily_caps={"web": 0, "news": 0}, clock=self.clock)
        with self.assertRaisesRegex(BudgetError, "attempt_budget_exhausted"):
            ledger.reserve("web")

    def test_concurrent_reservations_cannot_exceed_fixed_allowance(self):
        self.ledger()
        def reserve(_):
            try:
                return BudgetLedger(self.path, clock=self.clock).reserve("web")
            except BudgetError:
                return None
        with ThreadPoolExecutor(max_workers=20) as pool:
            results = list(pool.map(reserve, range(40)))
        self.assertEqual(sum(result is not None for result in results), 1)
        self.assertEqual(BudgetLedger(self.path).snapshot()["attempts"], 1)

    def test_concurrent_approved_workers_share_global_cap(self):
        # Accelerated deterministic wall time keeps this a fast offline contention test.
        base = time.monotonic_ns()
        clock = lambda: EPOCH + (time.monotonic_ns() - base) * 1000
        BudgetLedger.initialize_approved(self.path, approval_reference="fixture-seven-calls",
                    global_cap_micros=35_000, endpoint_daily_caps={"web": 7, "news": 7}, clock=clock)
        def dispatch(i):
            ledger = BudgetLedger(self.path, clock=clock)
            for _ in range(100):
                try:
                    attempt = ledger.reserve("web" if i % 2 else "news")
                    ledger.complete(attempt, status_class="success", http_status=200)
                    return True
                except BudgetError as error:
                    if error.code == "attempt_budget_exhausted":
                        return False
                    if error.code not in {"previous_attempt_unresolved", "shared_backoff"}:
                        raise
                    time.sleep(0.001)
            return False
        with ThreadPoolExecutor(max_workers=12) as pool:
            results = list(pool.map(dispatch, range(24)))
        self.assertEqual(sum(results), 7)
        self.assertEqual(BudgetLedger(self.path).snapshot()["conservative_reserved_micros"], 35_000)


class SecretTests(SecureTemporaryTest):
    def setUp(self):
        super().setUp()
        self.repo = self.directory / "repo"
        self.repo.mkdir(mode=0o700)
        (self.repo / "backend").mkdir(mode=0o700)
        subprocess.run(["git", "init", "--quiet", str(self.repo)], check=True, capture_output=True)
        (self.repo / ".gitignore").write_text("/backend/.env.brave\n/backend/.env.brave.*\n")
        self.secret = default_secret_path(self.repo)

    def test_hidden_file_round_trip_and_rotation_preserve_budget(self):
        ledger = self.ledger()
        ledger.reserve("web")
        self.assertEqual(secret_status(self.secret, self.repo), "unconfigured")
        write_secret(self.secret, FAKE_KEY, self.repo)
        self.assertEqual(self.secret.stat().st_mode & 0o777, 0o600)
        self.assertEqual(load_secret(self.secret, self.repo), FAKE_KEY)
        write_secret(self.secret, FAKE_KEY + "-rotation", self.repo)
        self.assertEqual(BudgetLedger(self.path).snapshot()["attempts"], 1)
        self.assertEqual(secret_status(self.secret, self.repo), "configured_unverified")

    def test_status_does_not_read_secret(self):
        write_secret(self.secret, FAKE_KEY, self.repo)
        with patch.object(Path, "read_text", side_effect=AssertionError("secret read")):
            self.assertEqual(secret_status(self.secret, self.repo), "configured_unverified")

    def test_symlink_hardlink_parent_and_permissions_are_refused(self):
        target = self.directory / "target"
        target.write_text("unrelated")
        target.chmod(0o600)
        self.secret.symlink_to(target)
        with self.assertRaises(SecretError):
            write_secret(self.secret, FAKE_KEY, self.repo)
        self.assertEqual(target.read_text(), "unrelated")
        self.secret.unlink()
        os.link(target, self.secret)
        with self.assertRaises(SecretError):
            write_secret(self.secret, FAKE_KEY, self.repo)
        self.secret.unlink()
        write_secret(self.secret, FAKE_KEY, self.repo)
        self.secret.chmod(0o644)
        with self.assertRaises(SecretError):
            load_secret(self.secret, self.repo)
        self.secret.chmod(0o600)
        (self.repo / "backend").chmod(0o777)
        with self.assertRaises(SecretError):
            write_secret(self.secret, FAKE_KEY, self.repo)

    def test_tracked_unignored_and_unrelated_paths_refused(self):
        (self.repo / ".gitignore").write_text("")
        with self.assertRaises(SecretError):
            write_secret(self.secret, FAKE_KEY, self.repo)
        (self.repo / ".gitignore").write_text("/backend/.env.brave\n")
        write_secret(self.secret, FAKE_KEY, self.repo)
        subprocess.run(["git", "-C", str(self.repo), "add", "--force", "backend/.env.brave"], check=True, capture_output=True)
        with self.assertRaises(SecretError):
            write_secret(self.secret, FAKE_KEY, self.repo)
        with self.assertRaises(SecretError):
            write_secret(self.repo / "backend" / ".env", FAKE_KEY, self.repo)

    def test_bad_inputs_are_sanitized(self):
        for key in ("", "short", "secret with spaces", "line1\nline2", "ü" * 12, "x" * 4097):
            with self.assertRaises(SecretError) as error:
                validate_key(key)
            self.assertEqual(str(error.exception), "invalid_secret")

    def test_common_git_directory_shares_allowance_across_fixture_worktrees(self):
        # Disposable test repository only; never creates a worktree of the app.
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=Fixture", "-c",
                        "user.email=fixture@example.invalid", "commit", "--quiet", "--allow-empty", "-m", "Fixture"],
                       check=True, capture_output=True)
        other = self.directory / "linked-worktree"
        subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "--quiet", "--detach", str(other)],
                       check=True, capture_output=True)
        primary_path = default_ledger_path(self.repo)
        self.assertEqual(primary_path, default_ledger_path(other))
        self.assertTrue(primary_path.is_relative_to(self.repo / ".git"))
        ledger = BudgetLedger.initialize_smoke(primary_path, clock=self.clock)
        ledger.reserve("web")
        self.assertEqual(BudgetLedger(default_ledger_path(other)).snapshot()["attempts"], 1)
        with self.assertRaises(BudgetError):
            BudgetLedger.initialize_smoke(default_ledger_path(other))

    def test_setup_refuses_noninteractive_and_arguments_without_echo(self):
        result = subprocess.run(["python3", "backend/setup_brave_secret.py", FAKE_KEY],
                                cwd=REPO, input="", capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn(FAKE_KEY, result.stdout + result.stderr)
        result = subprocess.run(["python3", "backend/setup_brave_secret.py"],
                                cwd=REPO, input="", capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


class ConfigurationTests(unittest.TestCase):
    def test_defaults_fixture_only_and_all_rights_unknown(self):
        config = SearchConfig()
        config.validate()
        self.assertEqual(config.live_development_cap_micros, 0)
        self.assertFalse(config.live_search)
        rights = load_rights(REPO / "backend/config/brave_rights.json")
        for gate in rights["gates"]:
            with self.assertRaises(ConfigurationError):
                require_right(rights, gate)

    def test_production_has_no_loopback_or_debug_endpoint(self):
        for url in ("http://example.com", "https://localhost", "https://127.0.0.1",
                    "https://[::1]", "https://10.0.0.1", "https://example.test", "https://user@example.com"):
            with self.assertRaises(ConfigurationError):
                validate_production_url(url)
        with self.assertRaises(ConfigurationError):
            SearchConfig(profile="production", environment="production", production_gateway_url="https://wingman.example.com").validate()

    def test_public_assets_contain_no_key_assignment(self):
        import re
        pattern = re.compile(rb"(?:X-Subscription-Token|BRAVE_API_KEY)\s*[:=]\s*[\"']?[A-Za-z0-9_-]{12,}")
        for directory in ("assets", "lib", "web"):
            for path in (REPO / directory).rglob("*"):
                if path.is_file() and path.suffix in {".dart", ".js", ".html", ".json", ".yaml", ".txt"}:
                    self.assertIsNone(pattern.search(path.read_bytes()), str(path.relative_to(REPO)))


if __name__ == "__main__":
    unittest.main()
