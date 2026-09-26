"""Actual adapter/ledger smoke orchestration with an injected offline transport."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from brave_smoke_test import run_smoke
from wingman_content.fetch import FetchResult
from wingman_search.budget import BudgetError, BudgetLedger
from wingman_search.provider import BraveProvider
from wingman_search.policy import SearchPolicy

REPO = Path(__file__).absolute().parents[2]
EPOCH = 1_790_380_800_000_000


class FixtureTransport:
    def __init__(self, reply_status=200, malformed=False):
        self.calls = []
        self.reply_status, self.malformed = reply_status, malformed

    def request(self, kind, params, key):
        # No real key is supplied; retaining parameters is test-only evidence.
        self.calls.append((kind, params, key == "fixture-key-not-real"))
        row = dict(title="Fixture Python documentation", description="Fixture text only.",
                   url="https://docs.python.org/3/")
        data = {"web": {"results": [row]}} if kind == "web" else {"results": [row]}
        body = b"malformed" if self.malformed else json.dumps(data).encode()
        return FetchResult(self.reply_status, {}, body)


class BraveSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = SearchPolicy()

    def setUp(self):
        (REPO / "work").mkdir(exist_ok=True)
        self.directory = Path(tempfile.mkdtemp(prefix="brave-smoke-fixture-", dir=REPO / "work"))
        self.now = EPOCH
        self.path = self.directory / "budget.sqlite3"
        self.ledger = BudgetLedger.initialize_smoke(self.path, clock=lambda: self.now)

    def tearDown(self):
        shutil.rmtree(self.directory)

    def run_fixture(self, transport):
        def sleep(seconds):
            self.now += int(seconds * 1_000_000)
        provider = BraveProvider(self.ledger, "fixture-key-not-real", transport=transport, policy=self.policy)
        with patch("wingman_search.secrets.load_secret", side_effect=AssertionError("No key reads in fixtures")), \
                patch("socket.create_connection", side_effect=AssertionError("No network in fixtures")):
            return run_smoke(self.ledger, provider, sleeper=sleep, clock=lambda: self.now * 1000)

    def test_actual_adapter_one_each_strict_count_one_then_rerun_refused(self):
        transport = FixtureTransport()
        evidence = self.run_fixture(transport)
        self.assertEqual([row["status"] for row in evidence], ["schema-success", "schema-success"])
        self.assertEqual([call[0] for call in transport.calls], ["web", "news"])
        for kind, params, fixture_key in transport.calls:
            self.assertEqual(params["count"], 1)
            self.assertEqual(params["safesearch"], "strict")
            self.assertEqual(params["offset"], 0)
            self.assertTrue(fixture_key)
        self.assertEqual(self.ledger.snapshot()["attempts"], 2)
        self.assertEqual(self.ledger.snapshot()["estimated_success_cost_micros"], 10_000)
        self.assertEqual(self.ledger.snapshot()["reconciled_attempts"], 0)
        with self.assertRaisesRegex(BudgetError, "smoke_already_started"):
            self.run_fixture(transport)
        self.assertEqual(len(transport.calls), 2)
        self.assertNotIn("Python documentation", json.dumps(evidence))
        self.assertNotIn(b"Python documentation", self.path.read_bytes())

    def test_first_auth_failure_stops_without_news_or_retry(self):
        transport = FixtureTransport(reply_status=401)
        evidence = self.run_fixture(transport)
        self.assertEqual(evidence[0]["status"], "provider-authentication")
        self.assertEqual(evidence[0]["httpStatus"], 401)
        self.assertEqual(len(transport.calls), 1)
        self.assertTrue(self.ledger.snapshot()["halted"])
        self.assertEqual(self.ledger.snapshot()["confirmed_successes"], 0)
        with self.assertRaisesRegex(BudgetError, "smoke_already_started"):
            self.run_fixture(transport)

    def test_schema_failure_stops_but_keeps_estimated_success_accounting(self):
        transport = FixtureTransport(malformed=True)
        evidence = self.run_fixture(transport)
        self.assertEqual(evidence[0]["status"], "malformed-response")
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(self.ledger.snapshot()["schema_successes"], 0)
        self.assertEqual(self.ledger.snapshot()["confirmed_successes"], 1)
        self.assertEqual(self.ledger.snapshot()["estimated_success_cost_micros"], 5_000)

    def test_transport_failure_is_unknown_not_confirmed_charge(self):
        class BrokenTransport:
            def request(self, *args):
                raise RuntimeError("Fixture transport failure with private contents")
        evidence = self.run_fixture(BrokenTransport())
        self.assertEqual(evidence[0]["status"], "transport-error")
        self.assertEqual(self.ledger.snapshot()["unknown_outcomes"], 1)
        self.assertEqual(self.ledger.snapshot()["estimated_success_cost_micros"], 0)
        self.assertNotIn("private contents", json.dumps(evidence))

    def test_metadata_command_runs_without_site_packages_or_credential_reads(self):
        result = subprocess.run(["python3", "-S", "backend/brave_smoke_test.py", "--status"],
                                cwd=REPO, capture_output=True, text=True, check=True)
        status = json.loads(result.stdout)
        self.assertIn(status["credential"], {"unconfigured", "configured_unverified", "unsafe_configuration"})
        self.assertNotIn("BRAVE_API_KEY", result.stdout)


if __name__ == "__main__":
    unittest.main()
