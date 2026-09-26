"""Approved-deployment GCS accounting with generation compare-and-swap.

No cloud client is created on import. Explicit project, bucket, operations
object and owner-approval evidence are required before constructing an adapter.
The retried transaction callback changes accounting only; the Brave request
always happens after reserve() returns a durably committed reservation.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import re
import uuid

from .budget import (BudgetError, LIST_RATE_MICROS, MICROS_PER_SECOND, NEWS_SLOTS, NEWS_INTERVAL_MICROS,
                     Reservation, STATUSES, rate_windows, utc_microseconds)

MAX_LEDGER_BYTES = 4 * 1024 * 1024
MAX_ATTEMPTS = 10_000  # Deliberately bounded initial pilot, not an unbounded history.
MAX_CAS_TRIES = 12
METRIC_NAMES = frozenset({"submitted", "completed", "failed", "web", "news"})
POLICY_FIELDS = frozenset({"identity", "approval", "global_cap_micros", "unit_cost_micros",
                          "endpoint_daily_caps", "created_at"})
STATE_FIELDS = POLICY_FIELDS | {"version", "profile", "environment", "next_id", "halted",
                               "next_allowed", "windows", "attempts", "metrics", "news_schedule"}
ATTEMPT_FIELDS = frozenset({"id", "endpoint", "date_bucket", "reserved_at", "reserved_cost",
                            "status_class", "http_status", "reconciled_cost"})


def validate_location(project, bucket, object_name, approval_reference):
    if (not isinstance(project, str) or not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", project)
            or not isinstance(bucket, str) or not re.fullmatch(r"[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]", bucket)
            or not isinstance(object_name, str)
            or not re.fullmatch(r"wingman-operations/[a-z0-9][a-z0-9_-]{0,79}\.json", object_name)
            or not isinstance(approval_reference, str)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,79}", approval_reference)):
        raise BudgetError("explicit_approved_shared_location_required")


def _integer(value, minimum=0):
    return type(value) is int and minimum <= value <= 9_000_000_000_000_000_000


def _clock(clock):
    value = clock()
    if not _integer(value):
        raise BudgetError("invalid_clock")
    return value


def _date(now):
    try:
        return datetime.fromtimestamp(now / MICROS_PER_SECOND, timezone.utc).date().isoformat()
    except (ValueError, OverflowError, OSError):
        raise BudgetError("invalid_clock") from None


def _valid_day(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%d")
        return True
    except ValueError:
        return False


def _encode(value):
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    if len(data) > MAX_LEDGER_BYTES:
        raise BudgetError("shared_ledger_capacity_exhausted")
    return data


def _pairs(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError()
        value[key] = item
    return value


def _decode(data):
    try:
        if not isinstance(data, bytes) or len(data) > MAX_LEDGER_BYTES:
            raise ValueError()
        return json.loads(data.decode("utf-8"), object_pairs_hook=_pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    except (ValueError, UnicodeError, RecursionError):
        raise BudgetError("shared_ledger_corrupt") from None


def _policy(state):
    return {name: state[name] for name in POLICY_FIELDS}


def _validate(state, marker, approval):
    try:
        if (not isinstance(state, dict) or set(state) != STATE_FIELDS
                or state["version"] != 1 or state["profile"] != "approved-production"
                or state["environment"] != "production"
                or not isinstance(marker, dict) or set(marker) != {"version", "policy"}
                or marker["version"] != 1 or marker["policy"] != _policy(state)
                or state["approval"] != approval
                or not isinstance(state["identity"], str)
                or not re.fullmatch(r"[a-f0-9]{32}", state["identity"])):
            raise ValueError()
        caps = state["endpoint_daily_caps"]
        if (not isinstance(caps, dict) or set(caps) != {"web", "news"}
                or any(not _integer(value) for value in caps.values())
                or not _integer(state["global_cap_micros"])
                or not _integer(state["unit_cost_micros"], 1)
                or not _integer(state["created_at"])
                or not _integer(state["next_allowed"])
                or type(state["halted"]) is not bool):
            raise ValueError()
        if not isinstance(state["attempts"], list) or len(state["attempts"]) > MAX_ATTEMPTS:
            raise ValueError()
        if type(state["next_id"]) is not int or state["next_id"] != len(state["attempts"]) + 1:
            raise ValueError()
        pending = 0
        total = 0
        daily = {}
        for expected_id, attempt in enumerate(state["attempts"], 1):
            if (not isinstance(attempt, dict) or set(attempt) != ATTEMPT_FIELDS
                    or type(attempt["id"]) is not int or attempt["id"] != expected_id
                    or attempt["endpoint"] not in {"web", "news"}
                    or not _valid_day(attempt["date_bucket"])
                    or not _integer(attempt["reserved_at"])
                    or attempt["date_bucket"] != _date(attempt["reserved_at"])
                    or type(attempt["reserved_cost"]) is not int
                    or attempt["reserved_cost"] != state["unit_cost_micros"]
                    or attempt["status_class"] not in STATUSES | {"pending"}
                    or (attempt["http_status"] is not None and
                        (type(attempt["http_status"]) is not int or not 100 <= attempt["http_status"] <= 599))
                    or (attempt["reconciled_cost"] is not None and not _integer(attempt["reconciled_cost"]))):
                raise ValueError()
            if attempt["status_class"] == "success" and not (
                    attempt["http_status"] is not None and 200 <= attempt["http_status"] <= 299):
                raise ValueError()
            if attempt["status_class"] == "pending":
                pending += 1
                if attempt["http_status"] is not None or attempt["reconciled_cost"] is not None:
                    raise ValueError()
            total += attempt["reserved_cost"]
            bucket = (attempt["date_bucket"], attempt["endpoint"])
            daily[bucket] = daily.get(bucket, 0) + 1
        if pending > 1 or total > state["global_cap_micros"] or any(
                value > caps[kind] for (_, kind), value in daily.items()):
            raise ValueError()
        if not isinstance(state["windows"], list) or len(state["windows"]) > 16:
            raise ValueError()
        for window in state["windows"]:
            if (set(window) != {"limit", "remaining", "reset_at", "period_seconds"}
                    or not _integer(window["limit"], 1) or not _integer(window["remaining"])
                    or window["remaining"] > window["limit"] or not _integer(window["reset_at"])
                    or (window["period_seconds"] is not None and not _integer(window["period_seconds"], 1))):
                raise ValueError()
        metrics = state["metrics"]
        if (not isinstance(state["news_schedule"], dict) or set(state["news_schedule"]) - NEWS_SLOTS
                or any(not _integer(value) for value in state["news_schedule"].values())):
            raise ValueError()
        if not isinstance(metrics, dict) or set(metrics) != {"daily", "archived"}:
            raise ValueError()
        if not isinstance(metrics["daily"], dict) or len(metrics["daily"]) > 90:
            raise ValueError()
        if any(not _valid_day(day) for day in metrics["daily"]):
            raise ValueError()
        for counts in [metrics["archived"], *metrics["daily"].values()]:
            if (not isinstance(counts, dict) or set(counts) != METRIC_NAMES
                    or any(not _integer(value) for value in counts.values())):
                raise ValueError()
        return state
    except (ValueError, TypeError, KeyError, AttributeError):
        raise BudgetError("shared_ledger_corrupt") from None


class GCSBudgetLedger:
    """A bounded pilot store. No automatic initialization, retry or quota leasing."""

    def __init__(self, *, project, bucket, object_name, approval_reference,
                 client=None, clock=utc_microseconds):
        validate_location(project, bucket, object_name, approval_reference)
        self.project, self.bucket_name = project, bucket
        self.object_name, self.approval = object_name, approval_reference
        self.marker_name = object_name + ".initialized"
        self.clock = clock
        try:
            if client is None:
                from google.cloud import storage
                client = storage.Client(project=project)
            self.bucket = client.bucket(bucket)
        except Exception:
            raise BudgetError("shared_ledger_client_unavailable") from None
        self._read_current()  # Read-only check; missing state never creates an allowance.

    @classmethod
    def initialize_approved(cls, *, project, bucket, object_name, approval_reference,
                            global_cap_micros, endpoint_daily_caps,
                            unit_cost_micros=LIST_RATE_MICROS, client=None, clock=utc_microseconds):
        validate_location(project, bucket, object_name, approval_reference)
        if (not _integer(global_cap_micros) or not _integer(unit_cost_micros, 1)
                or not isinstance(endpoint_daily_caps, dict) or set(endpoint_daily_caps) != {"web", "news"}
                or any(not _integer(value) for value in endpoint_daily_caps.values())):
            raise BudgetError("invalid_budget")
        # Explicit installation operation only; never reachable via a public route.
        state = dict(version=1, identity=uuid.uuid4().hex, profile="approved-production", environment="production",
                     approval=approval_reference, global_cap_micros=global_cap_micros,
                     unit_cost_micros=unit_cost_micros, endpoint_daily_caps=dict(endpoint_daily_caps),
                     created_at=_clock(clock), next_id=1, halted=False, next_allowed=0, windows=[], attempts=[],
                     news_schedule={},
                     metrics={"daily": {}, "archived": dict.fromkeys(METRIC_NAMES, 0)})
        marker = {"version": 1, "policy": _policy(state)}
        _validate(state, marker, approval_reference)
        try:
            if client is None:
                from google.cloud import storage
                client = storage.Client(project=project)
            target = client.bucket(bucket)
            # Marker first: even an uncertain/failed state write cannot replenish.
            target.blob(object_name + ".initialized").upload_from_string(
                _encode(marker), content_type="application/json", if_generation_match=0, timeout=10, retry=None)
            target.blob(object_name).upload_from_string(
                _encode(state), content_type="application/json", if_generation_match=0, timeout=10, retry=None)
        except Exception:
            raise BudgetError("shared_initialization_refused_preserve_existing_state") from None
        return cls(project=project, bucket=bucket, object_name=object_name,
                   approval_reference=approval_reference, client=client, clock=clock)

    def _read_object(self, name, max_bytes):
        blob = self.bucket.blob(name)
        blob.reload(timeout=10, retry=None)
        if not _integer(blob.size) or blob.size > max_bytes:
            raise BudgetError("shared_ledger_corrupt")
        generation = int(blob.generation)
        if generation < 1:
            raise BudgetError("shared_ledger_corrupt")
        data = blob.download_as_bytes(if_generation_match=generation, timeout=10, retry=None)
        if len(data) > max_bytes:
            raise BudgetError("shared_ledger_corrupt")
        return blob, generation, _decode(data)

    def _read_state(self):
        try:
            _, _, marker = self._read_object(self.marker_name, 4096)
            blob, generation, state = self._read_object(self.object_name, MAX_LEDGER_BYTES)
            return blob, generation, _validate(state, marker, self.approval), marker
        except BudgetError:
            raise
        except Exception as exc:
            if getattr(exc, "code", None) in (409, 412):
                raise  # Safe read-race may be retried by the transaction loop.
            raise BudgetError("shared_ledger_missing_or_unavailable") from None

    def _update(self, mutate):
        for _ in range(MAX_CAS_TRIES):
            try:
                blob, generation, state, marker = self._read_state()
                result = mutate(state)  # No network I/O inside this callback.
                _validate(state, marker, self.approval)
                blob.upload_from_string(_encode(state), content_type="application/json",
                                        if_generation_match=generation, timeout=10, retry=None)
                return result
            except BudgetError:
                raise
            except Exception as exc:
                if getattr(exc, "code", None) in (409, 412):
                    continue
                # A timeout may have committed. Never retry an uncertain write.
                raise BudgetError("shared_ledger_write_outcome_unknown") from None
        raise BudgetError("shared_ledger_contention")

    def _read_current(self):
        for _ in range(MAX_CAS_TRIES):
            try:
                return self._read_state()
            except BudgetError:
                raise
            except Exception as exc:
                if getattr(exc, "code", None) not in (409, 412):
                    raise BudgetError("shared_ledger_missing_or_unavailable") from None
        raise BudgetError("shared_ledger_contention")

    def reserve(self, endpoint):
        return self._reserve(endpoint)

    def reserve_scheduled(self, slot_id, interval_micros):
        if slot_id not in NEWS_SLOTS or type(interval_micros) is not int or interval_micros != NEWS_INTERVAL_MICROS:
            raise BudgetError("unreviewed_news_schedule")
        return self._reserve("news", schedule_slot=slot_id, interval_micros=interval_micros)

    def schedule_due(self, slot_id):
        if slot_id not in NEWS_SLOTS:
            raise BudgetError("unreviewed_news_schedule")
        _, _, state, _ = self._read_current()
        return state["news_schedule"].get(slot_id)

    def _reserve(self, endpoint, schedule_slot=None, interval_micros=None):
        if endpoint not in {"web", "news"}:
            raise BudgetError("unclassified_endpoint")
        def change(state):
            now = _clock(self.clock)
            day = _date(now)
            if schedule_slot is not None and now < state["news_schedule"].get(schedule_slot, 0):
                raise BudgetError("scheduled_news_not_due")
            if state["halted"]:
                raise BudgetError("operator_intervention_required")
            if any(row["status_class"] == "pending" for row in state["attempts"]):
                raise BudgetError("previous_attempt_unresolved")
            if now < state["next_allowed"]:
                raise BudgetError("shared_backoff")
            if len(state["attempts"]) >= MAX_ATTEMPTS:
                raise BudgetError("shared_ledger_capacity_exhausted")
            state["windows"] = [window for window in state["windows"] if now < window["reset_at"]]
            for window in state["windows"]:
                if window["remaining"] <= 0:
                    raise BudgetError("provider_quota_exhausted")
                window["remaining"] -= 1
            count = sum(row["endpoint"] == endpoint and row["date_bucket"] == day for row in state["attempts"])
            reserved = sum(row["reserved_cost"] for row in state["attempts"])
            if (count >= state["endpoint_daily_caps"][endpoint]
                    or reserved + state["unit_cost_micros"] > state["global_cap_micros"]):
                raise BudgetError("attempt_budget_exhausted")
            reservation = Reservation(state["next_id"], endpoint, state["unit_cost_micros"])
            state["attempts"].append(dict(id=reservation.id, endpoint=endpoint, date_bucket=day,
                                         reserved_at=now, reserved_cost=reservation.reserved_micros,
                                         status_class="pending", http_status=None, reconciled_cost=None))
            state["next_id"] += 1
            state["next_allowed"] = now + MICROS_PER_SECOND
            if schedule_slot is not None:
                state["news_schedule"][schedule_slot] = now + interval_micros
            return reservation
        return self._update(change)

    @staticmethod
    def _pending(state, reservation):
        if type(reservation.id) is not int or not 1 <= reservation.id < state["next_id"]:
            raise BudgetError("invalid_or_completed_reservation")
        row = state["attempts"][reservation.id - 1]
        if (row["status_class"] != "pending" or row["endpoint"] != reservation.endpoint
                or row["reserved_cost"] != reservation.reserved_micros):
            raise BudgetError("invalid_or_completed_reservation")
        return row

    def complete(self, reservation, *, status_class, http_status=None,
                 retry_after_seconds=None, rate_limit_headers=None):
        if status_class not in STATUSES or (http_status is not None and
                (type(http_status) is not int or not 100 <= http_status <= 599)):
            raise BudgetError("invalid_outcome")
        if status_class == "success" and (http_status is None or not 200 <= http_status <= 299):
            raise BudgetError("success_requires_received_2xx")
        # Parse only reviewed rate metadata; no arbitrary headers enter persistence.
        headers = dict(rate_limit_headers or {})
        if retry_after_seconds is not None:
            headers["retry-after"] = str(retry_after_seconds)
        def change(state):
            row = self._pending(state, reservation)
            now = _clock(self.clock)
            try:
                windows, next_allowed = rate_windows(headers, now)
            except BudgetError:
                windows, next_allowed = [], now
                state["halted"] = True
            row.update(status_class=status_class, http_status=http_status)
            state["halted"] = state["halted"] or status_class == "auth_error"
            state["next_allowed"] = max(state["next_allowed"], next_allowed)
            if windows:
                state["windows"] = windows
        return self._update(change)

    def reconcile(self, reservation_id, billed_micros):
        if type(reservation_id) is not int or not _integer(billed_micros):
            raise BudgetError("invalid_reconciliation")
        def change(state):
            if not 1 <= reservation_id < state["next_id"]:
                raise BudgetError("invalid_reconciliation")
            row = state["attempts"][reservation_id - 1]
            if row["status_class"] == "pending" or row["reconciled_cost"] is not None:
                raise BudgetError("invalid_reconciliation")
            row["reconciled_cost"] = billed_micros
        return self._update(change)

    def snapshot(self):
        _, _, state, _ = self._read_current()
        rows = state["attempts"]
        successes = [row for row in rows if row["http_status"] is not None and 200 <= row["http_status"] <= 299]
        unknown = [row for row in rows if row["http_status"] is None]
        return {"profile": state["profile"], "environment": "production", "attempts": len(rows),
                "unit_cost_micros": state["unit_cost_micros"], "approval_reference": state["approval"],
                "endpoint_attempts": {kind: sum(row["endpoint"] == kind for row in rows) for kind in ("web", "news")},
                "endpoint_caps": state["endpoint_daily_caps"], "global_cap_micros": state["global_cap_micros"],
                "conservative_reserved_micros": sum(row["reserved_cost"] for row in rows),
                "confirmed_successes": len(successes),
                "schema_successes": sum(row["status_class"] == "success" for row in rows),
                "estimated_success_cost_micros": sum(row["reserved_cost"] for row in successes),
                "unknown_outcomes": len(unknown),
                "unknown_reserved_micros": sum(row["reserved_cost"] for row in unknown),
                "reconciled_attempts": sum(row["reconciled_cost"] is not None for row in rows),
                "reconciled_billed_requests": sum((row["reconciled_cost"] or 0) > 0 for row in rows),
                "billing_reconciliation_complete": all(row["reconciled_cost"] is not None for row in rows),
                "reconciled_billed_micros": sum(row["reconciled_cost"] or 0 for row in rows),
                "halted": state["halted"], "next_allowed_utc_micros": state["next_allowed"],
                "datastore_cost_status": "not_reconciled", "datastore_cost_micros": None,
                "maximum_pilot_attempt_records": MAX_ATTEMPTS}

    def record_search_event(self, name):
        if name not in METRIC_NAMES:
            raise BudgetError("unreviewed_search_metric")
        def change(state):
            day = _date(_clock(self.clock))
            metrics = state["metrics"]
            counts = metrics["daily"].setdefault(day, dict.fromkeys(METRIC_NAMES, 0))
            counts[name] += 1
            # Preserve total denominators while bounding dated aggregate retention.
            while len(metrics["daily"]) > 90:
                oldest = metrics["daily"].pop(min(metrics["daily"]))
                for key in METRIC_NAMES:
                    metrics["archived"][key] += oldest[key]
        return self._update(change)

    def search_metrics(self):
        _, _, state, _ = self._read_current()
        metrics = state["metrics"]
        totals = dict(metrics["archived"])
        for counts in metrics["daily"].values():
            for name in METRIC_NAMES:
                totals[name] += counts[name]
        return dict(totals, scope="aggregate-request-counts", environment="production", durable=True,
                    daily=metrics["daily"], archived=metrics["archived"],
                    audienceVerification="not-a-unique-user-or-paid-audience-measure")
