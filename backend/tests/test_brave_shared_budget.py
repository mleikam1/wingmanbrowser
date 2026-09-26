"""Generation-CAS fixtures. Never constructs a Google client or contacts cloud."""
from concurrent.futures import ThreadPoolExecutor
import json
import threading
import time
import unittest
from unittest.mock import patch
from wingman_search.config import ConfigurationError, GATES, SearchConfig

from wingman_search.budget import BudgetError, Reservation
from wingman_search.shared_budget import GCSBudgetLedger, METRIC_NAMES, validate_location

LOCATION = dict(project="wingman-fixture", bucket="wingman-fixture-bucket",
                object_name="wingman-operations/brave-budget.json", approval_reference="fixture-only-no-live-approval")
EPOCH = 1_790_380_800_000_000


class CloudError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__("fixture-cloud-error")


class MemoryCAS:
    def __init__(self):
        self.objects, self.lock = {}, threading.RLock()
        self.next_generation, self.conflicts = 1, 0
        self.timeout_after_commit = False
        self.fail_state_init = False
        self.writes = []

    def bucket(self, name):
        if name != LOCATION["bucket"]:
            raise AssertionError("Unexpected fixture bucket")
        return self

    def blob(self, name):
        return MemoryBlob(self, name)


class MemoryBlob:
    def __init__(self, store, name):
        self.store, self.name = store, name

    def reload(self, **kwargs):
        with self.store.lock:
            if self.name not in self.store.objects:
                raise CloudError(404)
            self.generation, body = self.store.objects[self.name]
            self.size = len(body)

    def download_as_bytes(self, *, if_generation_match, **kwargs):
        with self.store.lock:
            generation, body = self.store.objects.get(self.name, (0, b""))
            if generation != if_generation_match:
                raise CloudError(412)
            return body

    def upload_from_string(self, data, *, content_type, if_generation_match, retry, timeout):
        assert retry is None and timeout == 10 and content_type == "application/json"
        with self.store.lock:
            if self.store.fail_state_init and not self.name.endswith(".initialized"):
                raise CloudError(503)
            current = self.store.objects.get(self.name, (0, b""))[0]
            if self.store.conflicts:
                self.store.conflicts -= 1
                raise CloudError(412)
            if current != if_generation_match:
                raise CloudError(412)
            generation = self.store.next_generation
            self.store.next_generation += 1
            self.store.objects[self.name] = (generation, data.encode() if isinstance(data, str) else data)
            self.generation = generation
            self.store.writes.append(self.name)
            if self.store.timeout_after_commit:
                self.store.timeout_after_commit = False
                raise CloudError(504)


class SharedBudgetTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryCAS()
        self.now = EPOCH

    def clock(self):
        return self.now

    def initialize(self, cap=10_000, caps=None):
        return GCSBudgetLedger.initialize_approved(**LOCATION, global_cap_micros=cap,
                   endpoint_daily_caps=caps or {"web": 1, "news": 1}, client=self.store, clock=self.clock)

    def open(self):
        return GCSBudgetLedger(**LOCATION, client=self.store, clock=self.clock)

    def test_explicit_location_required_before_cloud_client(self):
        for values in ({"project": ""}, {"bucket": ""}, {"object_name": "content/current.json"},
                       {"object_name": "wingman-operations/../reset.json"}, {"approval_reference": ""}):
            with self.assertRaisesRegex(BudgetError, "explicit_approved_shared_location_required"):
                GCSBudgetLedger(**dict(LOCATION, **values))

    def test_open_missing_state_never_initializes(self):
        with self.assertRaisesRegex(BudgetError, "shared_ledger_missing_or_unavailable"):
            self.open()
        self.assertEqual(self.store.writes, [])

    def test_immutable_marker_survives_missing_ledger_and_partial_init(self):
        ledger = self.initialize()
        self.assertEqual(ledger.snapshot()["attempts"], 0)
        del self.store.objects[LOCATION["object_name"]]
        with self.assertRaises(BudgetError):
            self.open()
        with self.assertRaisesRegex(BudgetError, "shared_initialization_refused"):
            self.initialize()
        self.assertNotIn(LOCATION["object_name"], self.store.objects)
        self.store = MemoryCAS()
        self.store.fail_state_init = True
        with self.assertRaises(BudgetError):
            self.initialize()
        self.assertEqual(list(self.store.objects), [LOCATION["object_name"] + ".initialized"])
        self.store.fail_state_init = False
        with self.assertRaises(BudgetError):
            self.initialize()

    def test_concurrent_workers_share_global_and_endpoint_caps(self):
        self.initialize(cap=35_000, caps={"web": 4, "news": 3})
        clock_lock = threading.Lock()
        def clock():
            with clock_lock:
                self.now += 1_000_000
                return self.now
        def dispatch(index):
            ledger = GCSBudgetLedger(**LOCATION, client=self.store, clock=clock)
            for _ in range(300):
                try:
                    reservation = ledger.reserve("web" if index % 2 else "news")
                    ledger.complete(reservation, status_class="success", http_status=200)
                    return True
                except BudgetError as error:
                    if error.code == "attempt_budget_exhausted":
                        return False
                    if error.code not in {"previous_attempt_unresolved", "shared_backoff", "shared_ledger_contention"}:
                        raise
                    time.sleep(0.0001)
            raise AssertionError("Fixture worker made no progress")
        with ThreadPoolExecutor(max_workers=20) as workers:
            results = list(workers.map(dispatch, range(40)))
        self.assertEqual(sum(results), 7)
        report = self.open().snapshot()
        self.assertEqual(report["endpoint_attempts"], {"web": 4, "news": 3})
        self.assertEqual(report["conservative_reserved_micros"], 35_000)
        self.assertEqual(report["confirmed_successes"], 7)

    def test_cas_retries_accounting_once_without_dispatch_callback(self):
        ledger = self.initialize()
        self.store.conflicts = 3
        reservation = ledger.reserve("web")
        self.assertEqual(reservation.id, 1)
        self.assertEqual(ledger.snapshot()["attempts"], 1)
        self.assertEqual(self.store.conflicts, 0)

    def test_unknown_commit_stays_reserved_and_never_retries(self):
        ledger = self.initialize()
        writes = len(self.store.writes)
        self.store.timeout_after_commit = True
        with self.assertRaisesRegex(BudgetError, "shared_ledger_write_outcome_unknown"):
            ledger.reserve("web")
        self.assertEqual(len(self.store.writes), writes + 1)
        self.assertEqual(self.open().snapshot()["attempts"], 1)
        self.assertEqual(self.open().snapshot()["unknown_outcomes"], 1)
        self.now += 5_000_000
        with self.assertRaisesRegex(BudgetError, "previous_attempt_unresolved"):
            self.open().reserve("news")

    def test_unknown_completion_commit_not_replayed_or_refunded(self):
        ledger = self.initialize()
        reservation = ledger.reserve("web")
        self.store.timeout_after_commit = True
        with self.assertRaises(BudgetError):
            ledger.complete(reservation, status_class="success", http_status=200)
        self.assertEqual(ledger.snapshot()["confirmed_successes"], 1)
        with self.assertRaisesRegex(BudgetError, "invalid_or_completed_reservation"):
            self.open().complete(reservation, status_class="transport_error")

    def test_completed_and_wrong_reservation_are_fenced(self):
        ledger = self.initialize()
        web = ledger.reserve("web")
        with self.assertRaises(BudgetError):
            ledger.complete(Reservation(web.id, "news", web.reserved_micros), status_class="unknown")
        ledger.complete(web, status_class="success", http_status=200)
        self.now += 2_000_000
        news = self.open().reserve("news")
        with self.assertRaises(BudgetError):
            ledger.complete(web, status_class="http_error", http_status=500)
        self.open().complete(news, status_class="success", http_status=200)
        self.assertEqual(ledger.snapshot()["confirmed_successes"], 2)

    def test_unknown_vs_2xx_bad_schema_vs_reconciliation(self):
        ledger = self.initialize()
        web = ledger.reserve("web")
        ledger.complete(web, status_class="transport_error")
        self.now += 2_000_000
        news = ledger.reserve("news")
        ledger.complete(news, status_class="malformed_response", http_status=200)
        report = ledger.snapshot()
        self.assertEqual(report["unknown_reserved_micros"], 5000)
        self.assertEqual(report["estimated_success_cost_micros"], 5000)
        self.assertEqual(report["schema_successes"], 0)
        self.assertIsNone(report["datastore_cost_micros"])
        ledger.reconcile(web.id, 0)
        self.assertEqual(ledger.snapshot()["conservative_reserved_micros"], 10_000)
        self.assertEqual(ledger.snapshot()["reconciled_attempts"], 1)

    def test_rate_windows_and_backoff_are_shared(self):
        ledger = self.initialize()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200,
                        rate_limit_headers={"X-RateLimit-Limit": "1,2", "X-RateLimit-Remaining": "0,0",
                                            "X-RateLimit-Reset": "1,60", "X-RateLimit-Policy": "1;w=1,2;w=60",
                                            "Retry-After": "10"})
        self.now += 2_000_000
        with self.assertRaisesRegex(BudgetError, "shared_backoff"):
            self.open().reserve("news")
        self.now += 10_000_000
        with self.assertRaisesRegex(BudgetError, "provider_quota_exhausted"):
            self.open().reserve("news")
        self.now += 60_000_000
        self.open().reserve("news")

    def test_auth_and_malformed_rate_metadata_pause(self):
        ledger = self.initialize()
        ledger.complete(ledger.reserve("web"), status_class="auth_error", http_status=403)
        self.now += 5_000_000
        with self.assertRaisesRegex(BudgetError, "operator_intervention_required"):
            self.open().reserve("news")
        self.store = MemoryCAS()
        ledger = self.initialize()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200,
                        rate_limit_headers={"x-ratelimit-limit": "bad"})
        self.assertTrue(ledger.snapshot()["halted"])

    def test_corruption_or_changed_budget_does_not_grant_dispatch(self):
        self.initialize()
        generation, body = self.store.objects[LOCATION["object_name"]]
        state = json.loads(body)
        state["global_cap_micros"] = 500_000
        self.store.objects[LOCATION["object_name"]] = (generation, json.dumps(state).encode())
        with self.assertRaisesRegex(BudgetError, "shared_ledger_corrupt"):
            self.open()
        self.store.objects[LOCATION["object_name"]] = (generation, b"not json")
        with self.assertRaisesRegex(BudgetError, "shared_ledger_corrupt"):
            self.open()

    def test_no_queries_secrets_or_consumer_identifiers_persist(self):
        ledger = self.initialize()
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200,
                        rate_limit_headers={"Set-Cookie": "CANARY_PRIVATE", "X-Subscription-Token": "CANARY_SECRET"})
        ledger.record_search_event("submitted")
        with self.assertRaises(BudgetError):
            ledger.record_search_event("query:CANARY_QUERY")
        blob = b"".join(body for _, body in self.store.objects.values())
        for value in (b"CANARY", b"query", b"cookie", b"subscription", b"client_ip", b"referrer"):
            self.assertNotIn(value, blob)

    def test_search_metrics_durable_concurrent_and_bounded_with_total_preserved(self):
        ledger = self.initialize()
        with ThreadPoolExecutor(max_workers=12) as pool:
            list(pool.map(lambda _: self.open().record_search_event("submitted"), range(40)))
        report = self.open().search_metrics()
        self.assertEqual(report["submitted"], 40)
        self.assertTrue(report["durable"])
        for _ in range(95):
            self.now += 86_400_000_000
            ledger.record_search_event("submitted")
        report = ledger.search_metrics()
        self.assertEqual(report["submitted"], 135)
        self.assertEqual(len(report["daily"]), 90)
        self.assertEqual(set(report["archived"]), METRIC_NAMES)

    def test_capacity_is_fail_closed_and_daily_reset_cannot_reset_total(self):
        ledger = self.initialize(cap=5_000)
        ledger.complete(ledger.reserve("web"), status_class="success", http_status=200)
        self.now += 86_400_000_000
        with self.assertRaisesRegex(BudgetError, "attempt_budget_exhausted"):
            ledger.reserve("web")
        with patch("wingman_search.shared_budget.MAX_ATTEMPTS", 1):
            with self.assertRaisesRegex(BudgetError, "shared_ledger_capacity_exhausted"):
                ledger.reserve("news")

    def test_scheduled_slot_is_atomic_shared_and_not_reset_by_a_new_worker(self):
        ledger = self.initialize(cap=15_000, caps={"web": 1, "news": 2})
        slot = "brave-general"
        self.assertIsNone(ledger.schedule_due(slot))
        first = ledger.reserve_scheduled(slot, 7_200_000_000)
        ledger.complete(first, status_class="transport_error")
        self.assertEqual(self.open().schedule_due(slot), EPOCH + 7_200_000_000)
        self.now += 2_000_000
        with self.assertRaisesRegex(BudgetError, "scheduled_news_not_due"):
            self.open().reserve_scheduled(slot, 7_200_000_000)
        web = self.open().reserve("web")
        ledger.complete(web, status_class="success", http_status=200)
        self.now += 7_200_000_000
        ledger.reserve_scheduled(slot, 7_200_000_000)
        self.assertEqual(ledger.snapshot()["endpoint_attempts"], {"web": 1, "news": 2})

    def test_production_configuration_requires_all_evidence_but_no_ad_billing(self):
        settings = dict(profile="production", environment="production", live_search=True,
                        production_gateway_url="https://search.wingman.example.com",
                        shared_ledger_kind="gcs", shared_project=LOCATION["project"],
                        shared_bucket=LOCATION["bucket"], shared_object=LOCATION["object_name"],
                        deployment_approval_reference="fixture-deployment-approval",
                        provider_spend_approval_reference=LOCATION["approval_reference"],
                        production_cap_micros=10_000,
                        secret_manager_reference="projects/wingman-fixture/secrets/brave/versions/1",
                        rights_register_path="fixture-only-register.json")
        rights = {"approved_domains": ["search.wingman.example.com"], "gates": {
            gate: {"enabled": gate == "live_search", "authorization_status": "approved" if gate == "live_search" else "unknown",
                   "evidence_reference": "fixture-display-approval" if gate == "live_search" else None}
            for gate in GATES}}
        with patch("wingman_search.config.load_rights", return_value=rights):
            SearchConfig(**settings).validate()
            for missing in ("deployment_approval_reference", "provider_spend_approval_reference",
                            "shared_project", "secret_manager_reference", "rights_register_path"):
                with self.assertRaises(ConfigurationError):
                    SearchConfig(**dict(settings, **{missing: None})).validate()
            with self.assertRaises(ConfigurationError):
                SearchConfig(**dict(settings, production_billing=True)).validate()
            with self.assertRaises(ConfigurationError):
                SearchConfig(**dict(settings, cached_news=True)).validate()
            with self.assertRaises(ConfigurationError):
                SearchConfig(**dict(settings, production_cap_micros=0)).validate()
            rights['approved_domains'] = 'prefix-search.wingman.example.com-suffix'
            with self.assertRaises(ConfigurationError):
                SearchConfig(**settings).validate()


if __name__ == "__main__":
    unittest.main()
