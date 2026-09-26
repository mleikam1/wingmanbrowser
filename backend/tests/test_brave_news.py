"""Shared news tests with actual adapter, durable local budget and no provider I/O."""
import copy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from wingman_content.brave import BraveNewsProvider, EDITORIAL_QUERIES, source_definition
from wingman_content.fetch import FetchResult
from wingman_content.provider import CompositeNewsProvider, ingest, public_snapshot
from wingman_content.server import SnapshotReader
from wingman_content.store import LocalStore
from wingman_search.budget import BudgetError, BudgetLedger, NEWS_INTERVAL_MICROS
from wingman_search.config import load_rights
from wingman_search.contracts import SearchError
from wingman_search.provider import BraveProvider
from wingman_search.policy import SearchPolicy

ROOT = Path(__file__).absolute().parents[2]


class NewsTransport:
    def __init__(self):
        self.calls, self.status, self.body = [], 200, None
    def request(self, kind, params, key):
        self.calls.append((kind, dict(params)))
        row = {"title": "Science research reporting", "description": "New research findings.",
               "url": "https://docs.python.org/articles/research?utm_source=fixture",
               "thumbnail": {"src": "https://tracker.example.com/unlicensed-image"},
               "page_age": "2020-01-01T00:00:00Z" if self.body == "old" else None}
        body = b"bad json" if self.body == "bad" else json.dumps({"results": [] if self.body == "empty" else [row]}).encode()
        return FetchResult(self.status, {}, body)


class BraveNewsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.policy = SearchPolicy()

    def setUp(self):
        (ROOT / "work").mkdir(exist_ok=True)
        self.directory = Path(tempfile.mkdtemp(prefix="brave-news-", dir=ROOT / "work"))
        self.now = datetime.now(timezone.utc).replace(microsecond=0)
        self.ledger = BudgetLedger.initialize_approved(self.directory / "budget.sqlite3", approval_reference="fixture-news",
                global_cap_micros=500_000, endpoint_daily_caps={"web": 50, "news": 50}, clock=lambda: int(self.now.timestamp() * 1_000_000))
        self.rights = load_rights(ROOT / "backend/config/brave_rights.json")
        self.rights.update(shared_news_use="approved", cdn_fanout="approved", storage_duration_seconds=86400)
        self.rights["gates"]["cached_news"] = dict(enabled=True, authorization_status="approved", evidence_reference="fixture-grant")
        self.source = source_definition()
        self.source.update(enabled=True, sharedNewsGrant=dict(status="approved", reference="fixture-grant", retentionSeconds=86400))
        self.source["rights"].update(titles=True, excerpts=True)
        self.transport = NewsTransport()
        self.provider = BraveProvider(self.ledger, "fixture-not-real", transport=self.transport, policy=self.policy)
        self.news = BraveNewsProvider(self.provider, rights_loader=lambda: self.rights)
        self.news.bind_writer_guard(lambda: None)

    def tearDown(self):
        shutil.rmtree(self.directory)

    def test_missing_rights_or_key_never_dispatch_and_factory_not_called(self):
        invoked = []
        unconfigured = BraveNewsProvider(provider_factory=lambda: invoked.append(True), rights_loader=lambda: {})
        self.assertEqual(unconfigured.refresh(self.source, {}, self.now)["items"], [])
        self.assertEqual(invoked, [])
        unconfigured = BraveNewsProvider(rights_loader=lambda: self.rights)
        self.assertEqual(unconfigured.refresh(self.source, {}, self.now)["error"], "brave-unconfigured")
        self.assertEqual(self.ledger.snapshot()["attempts"], 0)

    def test_actual_adapter_uses_fixed_strict_news_and_provenance(self):
        state = self.news.refresh(self.source, {}, self.now)
        self.assertEqual(len(self.transport.calls), 1)
        kind, params = self.transport.calls[0]
        self.assertEqual(kind, "news")
        self.assertEqual(params["safesearch"], "strict")
        self.assertEqual(params["offset"], 0)
        self.assertIn(params["q"], EDITORIAL_QUERIES.values())
        self.assertNotIn("result_filter", params)
        item = state["items"][0]
        self.assertIsNone(item["publishedAt"])
        self.assertEqual(item["discoveredAt"], item["fetchedAt"])
        self.assertEqual(item["publisherName"], "docs.python.org")
        self.assertEqual(item["canonicalUrl"], "https://docs.python.org/articles/research")
        self.assertIsNone(item["image"])
        self.assertNotIn("unlicensed-image", json.dumps(state))
        self.assertEqual(self.ledger.snapshot()["attempts"], 1)

    def test_schedule_survives_content_deletion_restart_and_failure(self):
        self.transport.status = 500
        state = self.news.refresh(self.source, {}, self.now)
        self.assertEqual(len(self.transport.calls), 1)
        self.now += timedelta(seconds=2)
        self.news.refresh(self.source, {}, self.now)  # lost content does not reset operational due slot
        self.assertEqual(len(self.transport.calls), 1)
        restarted = BudgetLedger(self.directory / "budget.sqlite3", clock=lambda: int(self.now.timestamp() * 1_000_000))
        self.assertEqual(restarted.snapshot()["attempts"], 1)
        self.assertTrue(state["error"])

    def test_same_slot_cannot_spend_smoke_allowance(self):
        smoke = BudgetLedger.initialize_smoke(self.directory / "smoke.sqlite3")
        for operation in (lambda: smoke.schedule_due("brave-general"),
                          lambda: smoke.reserve_scheduled("brave-general", NEWS_INTERVAL_MICROS)):
            with self.assertRaisesRegex(BudgetError, "smoke_cannot_schedule_news"):
                operation()
        self.assertEqual(smoke.snapshot()["attempts"], 0)

    def test_provider_runtime_gate_and_writer_fence_both_checked_before_reserve(self):
        calls = []
        self.news.bind_writer_guard(lambda: calls.append("writer"))
        def revoked():
            calls.append("runtime")
            raise SearchError("configuration-required", 503)
        self.provider.before_request = revoked
        result = self.news.refresh(self.source, {}, self.now)
        self.assertIn("writer", calls)
        self.assertIn("runtime", calls)
        self.assertEqual(result["error"], "configuration-required")
        self.assertEqual(self.ledger.snapshot()["attempts"], 0)

    def test_rights_revocation_purges_before_due_and_excerpt_revocation_redacts(self):
        state = self.news.refresh(self.source, {}, self.now)
        self.assertIn("excerpt", state["items"][0])
        self.source["rights"]["excerpts"] = False
        redacted = self.news.retain_authorized(self.source, state, self.now)
        self.assertNotIn("excerpt", redacted["items"][0])
        self.rights["gates"]["cached_news"]["enabled"] = False
        revoked = self.news.retain_authorized(self.source, state, self.now)
        self.assertEqual(revoked["items"], [])
        self.assertEqual(revoked["bravePools"], {})
        self.assertTrue(revoked["rightsBlocked"])

    def test_republication_and_duplicate_categories_never_extend_original_retention(self):
        state = self.news.refresh(self.source, {}, self.now)
        item = state["items"][0]
        self.now += timedelta(minutes=15)
        second = self.news.refresh(self.source, state, self.now)
        self.assertEqual(len(second["items"]), 1)
        self.assertEqual(second["items"][0]["fetchedAt"], item["fetchedAt"])
        self.assertEqual(second["items"][0]["expiresAt"], item["expiresAt"])
        self.assertEqual(len(second["items"][0]["providerCategories"]), 2)
        self.now += timedelta(hours=25)
        self.assertEqual(self.news.retain_authorized(self.source, second, self.now)["items"], [])

    def test_grant_revoked_during_received_response_never_enters_cache(self):
        prior = self.news.refresh(self.source, {}, self.now)
        self.now += timedelta(minutes=15)
        original = self.transport.request
        def revoked_after_response(*args):
            response = original(*args)
            self.rights["gates"]["cached_news"]["enabled"] = False
            return response
        self.transport.request = revoked_after_response
        result = self.news.refresh(self.source, prior, self.now)
        self.assertEqual(result["items"], [])
        self.assertTrue(result["rightsBlocked"])
        self.assertEqual(self.ledger.snapshot()["confirmed_successes"], 2)

    def test_empty_malformed_old_timestamps_and_no_retry(self):
        for mode in ("empty", "bad", "old"):
            with self.subTest(mode=mode):
                self.transport.body = mode
                state = self.news.refresh(self.source, {}, self.now)
                self.assertEqual(state["items"], [])
                self.now += timedelta(minutes=15)
        self.assertEqual(len(self.transport.calls), 3)

    def test_composite_preserves_standby_without_duplicate_paid_poll(self):
        class Standby:
            def refresh(self, *args):
                raise AssertionError("Inactive provider polled")
        composite = CompositeNewsProvider(Standby(), Standby(), self.news, primary_shared_provider="brave")
        state = composite.refresh({"providerId": "currents"}, {}, self.now)
        self.assertEqual(state["error"], "editorial-provider-standby")
        self.assertEqual(len(self.transport.calls), 0)

    def test_ingest_and_ten_thousand_reads_make_one_paid_call_and_revocation_is_immediate(self):
        class NoRss:
            def refresh(self, *args):
                raise AssertionError("No RSS fixture sources")
        config = {"sources": [self.source], "primarySharedProvider": "brave"}
        store = LocalStore(self.directory / "content")
        composite = CompositeNewsProvider(NoRss(), None, self.news)
        snapshot, _ = ingest(config, store, composite, self.now)
        self.assertEqual(len(snapshot["items"]), 1)
        reader = SnapshotReader(store, brave_rights_loader=lambda: self.rights)
        for _ in range(10_000):
            self.assertEqual(len(reader.read()["items"]), 1)
        self.assertEqual(len(self.transport.calls), 1)
        self.rights["gates"]["cached_news"]["enabled"] = False
        self.assertEqual(reader.read()["items"], [])
        self.now += timedelta(seconds=1)
        snapshot, _ = ingest(config, store, composite, self.now)
        self.assertEqual(snapshot["items"], [])
        self.assertEqual(store.read()["states"]["brave-news"]["bravePools"], {})
        self.assertEqual(len(self.transport.calls), 1)

    def test_reader_rejects_cached_representation_after_grant_reference_changes(self):
        state = self.news.refresh(self.source, {}, self.now)
        snapshot = public_snapshot({'sources': [self.source]}, {'brave-news': state}, self.now)
        store = LocalStore(self.directory / 'content')
        store.write({'snapshot': snapshot})
        reader = SnapshotReader(store, brave_rights_loader=lambda: self.rights)
        self.assertEqual(len(reader.read()['items']), 1)
        self.rights['gates']['cached_news']['evidence_reference'] = 'new-grant'
        self.assertEqual(reader.read()['items'], [])
        self.assertEqual(len(self.transport.calls), 1)


if __name__ == "__main__":
    unittest.main()
