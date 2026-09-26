"""One owner-authorized local evaluation, never a production spending store.

No query, response body, credential, client identity or free-form operator text
is retained. The legacy smoke database participates in the same SQLite commit
when its unused allowance is retired; its records and marker are preserved.
"""
from __future__ import annotations

from contextlib import contextmanager
import json
import os
from pathlib import Path
import sqlite3
import uuid

from .budget import (BudgetError, BudgetLedger, Reservation, STATUSES, _now,
                     _secure, default_ledger_path, rate_windows, utc_microseconds)

GRANT_ID = "wingman-brave-local-live-v3-20260926"
MAX_ATTEMPTS = 100
MAX_AUTOMATED_ATTEMPTS = 20
MAX_COST_MICROS = 500_000
UNIT_COST_MICROS = 5_000
LIFETIME_MICROS = 7 * 86_400_000_000
PACE_MICROS = 2_000_000
ACTORS = frozenset({"automated", "manual"})
CORRECTIONS = {
    "authentication": {"credential-updated"},
    "account-permission": {"account-corrected", "credential-updated"},
    "request-validation": {"request-corrected"},
    "response-schema": {"schema-corrected"},
    "rate-metadata": {"rate-metadata-corrected"},
    "previous-attempt-unresolved": {"transport-reviewed"},
}


def default_local_ledger_path(repo_root: Path) -> Path:
    return default_ledger_path(repo_root).with_name("brave-local-live-v3-20260926.sqlite3")


def _actor(actor):
    if actor not in ACTORS:
        raise BudgetError("invalid_local_request_actor")


def _write_new(path, content):
    _secure(path, False)
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
    except OSError:
        raise BudgetError("initialization_refused_preserve_existing_ledger") from None


def _legacy_state(db, marker):
    row = db.execute("SELECT * FROM legacy.state WHERE id=1").fetchone()
    if (row is None or row["version"] != 1 or row["profile"] != "smoke"
            or row["approval"] != "launcher-v2-two-request-smoke"
            or row["global_cap"] != 10_000 or row["unit_cost"] != UNIT_COST_MICROS
            or json.loads(row["caps"]) != {"web": 1, "news": 1}
            or marker.stat().st_size > 128
            or marker.read_text(encoding="ascii") != row["identity"]):
        raise BudgetError("legacy_accounting_requires_review")
    return row


def _rows(db):
    # Reconciliations to old attempts remain authoritative; never copy or erase.
    old = [dict(row, actor="automated", legacy=True) for row in db.execute(
        "SELECT * FROM legacy.attempts ORDER BY id")]
    new = [dict(row, legacy=False) for row in db.execute("SELECT * FROM main.attempts ORDER BY id")]
    return old + new


def _check_rows(rows):
    if len(rows) > MAX_ATTEMPTS:
        raise BudgetError("corrupt_local_evaluation_ledger")
    for row in rows:
        if (row["endpoint"] not in {"web", "news"} or row["actor"] not in ACTORS
                or row["status_class"] not in STATUSES | {"pending"}
                or type(row["reserved_cost"]) is not int or row["reserved_cost"] <= 0
                or (row["http_status"] is not None and not 100 <= row["http_status"] <= 599)
                or (row["reconciled_cost"] is not None and row["reconciled_cost"] < 0)):
            raise BudgetError("corrupt_local_evaluation_ledger")


def _pause_for(status_class, http_status):
    if http_status == 401:
        return "authentication"
    if http_status in {402, 403}:
        return "account-permission"
    if http_status in {400, 422}:
        return "request-validation"
    if status_class == "auth_error":
        return "authentication"
    if status_class == "malformed_response":
        return "response-schema"
    return None


class LocalEvaluationLedger:
    def __init__(self, path: Path, *, actor="automated", environment="local",
                 clock=utc_microseconds):
        _actor(actor)
        if environment != "local":
            raise BudgetError("production_requires_shared_ledger")
        self.path = Path(path).absolute()
        self.marker = self.path.with_name(self.path.name + ".initialized")
        self.legacy_path = self.path.with_name("brave_budget.sqlite3")
        self.legacy_marker = self.legacy_path.with_name(self.legacy_path.name + ".initialized")
        self.actor, self.clock = actor, clock
        with self._transaction() as db:
            self._state(db)

    @classmethod
    def initialize(cls, path: Path, *, actor="automated", unit_cost_micros=UNIT_COST_MICROS,
                   environment="local", clock=utc_microseconds):
        """Explicit owner entry. Repeat calls only open the exact existing grant.

        A marker without its database is never rebuilt. The legacy smoke is
        retired even when unused; creating a zero-attempt smoke tombstone keeps
        old worktree code from initializing a second allowance later.
        """
        _actor(actor)
        if environment != "local":
            raise BudgetError("production_requires_shared_ledger")
        if type(unit_cost_micros) is not int or not 0 < unit_cost_micros <= UNIT_COST_MICROS:
            raise BudgetError("higher_unit_price_requires_owner_approval")
        path = Path(path).absolute()
        marker = path.with_name(path.name + ".initialized")
        if path.exists() or marker.exists() or path.is_symlink() or marker.is_symlink():
            existing = cls(path, actor=actor, clock=clock)
            if existing.snapshot()["unit_cost_micros"] != unit_cost_micros:
                raise BudgetError("existing_grant_price_mismatch")
            return existing
        legacy_path = path.with_name("brave_budget.sqlite3")
        legacy_marker = legacy_path.with_name(legacy_path.name + ".initialized")
        # This validates every existing legacy row/schema/path without touching
        # credentials. One missing file in an established pair always refuses.
        if any(p.exists() or p.is_symlink() for p in (legacy_path, legacy_marker)):
            legacy = BudgetLedger(legacy_path, clock=clock)
        else:
            legacy = BudgetLedger.initialize_smoke(legacy_path, clock=clock)
        legacy_state = legacy.snapshot()
        if legacy_state["profile"] != "smoke":
            raise BudgetError("legacy_accounting_requires_review")
        with legacy._transaction() as old_db:
            if old_db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='local_evaluation_binding'").fetchone():
                raise BudgetError("existing_local_grant_requires_original_accounting")
            if old_db.execute("SELECT 1 FROM main.attempts WHERE status_class='pending'").fetchone():
                raise BudgetError("legacy_attempt_unresolved")
        created = _now(clock)
        identity = uuid.uuid4().hex
        marker_data = dict(version=1, grant_id=GRANT_ID, identity=identity,
                           created=created, expires=created + LIFETIME_MICROS,
                           unit_cost=unit_cost_micros)
        _write_new(marker, json.dumps(marker_data, sort_keys=True))
        _write_new(path, "")
        db = None
        try:
            db = sqlite3.connect(path.as_uri() + "?mode=rw", uri=True, timeout=15)
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA journal_mode=DELETE")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("ATTACH DATABASE ? AS legacy", (legacy_path.as_uri() + "?mode=rw",))
            db.execute("PRAGMA legacy.journal_mode=DELETE")
            db.execute("PRAGMA legacy.synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            old = _legacy_state(db, legacy_marker)
            if db.execute("SELECT 1 FROM legacy.sqlite_master WHERE type='table' AND name='local_evaluation_binding'").fetchone():
                raise BudgetError("existing_local_grant_requires_original_accounting")
            if db.execute("SELECT COUNT(*) FROM legacy.attempts WHERE status_class='pending'").fetchone()[0]:
                raise BudgetError("legacy_attempt_unresolved")
            old_rows = [dict(r, actor="automated", legacy=True) for r in db.execute("SELECT * FROM legacy.attempts")]
            _check_rows(old_rows)
            if len(old_rows) > 2:
                raise BudgetError("legacy_accounting_requires_review")
            # CREATE statements are transactional; executescript would commit
            # early and break the multi-database retirement boundary.
            db.execute("""CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1),
                marker TEXT NOT NULL, legacy_identity TEXT NOT NULL,
                legacy_attempts INTEGER NOT NULL, pause_reason TEXT,
                next_allowed INTEGER NOT NULL, windows TEXT NOT NULL,
                last_observed INTEGER NOT NULL, rate_metadata_invalid INTEGER NOT NULL)""")
            db.execute("""CREATE TABLE attempts (id INTEGER PRIMARY KEY,
                endpoint TEXT NOT NULL, actor TEXT NOT NULL,
                reserved_at INTEGER NOT NULL, reserved_cost INTEGER NOT NULL,
                status_class TEXT NOT NULL DEFAULT 'pending', http_status INTEGER,
                reconciled_cost INTEGER)""")
            db.execute("""CREATE TABLE corrections (id INTEGER PRIMARY KEY,
                corrected_at INTEGER NOT NULL, reason TEXT NOT NULL, correction TEXT NOT NULL)""")
            pause = None
            for row in old_rows:
                pause = _pause_for(row["status_class"], row["http_status"]) or pause
            if old["halted"] and pause is None:
                # A legacy stop can represent malformed quota metadata, which
                # the old schema did not distinguish from other failures.
                pause = "rate-metadata" if all(row["status_class"] == "success" for row in old_rows) else "previous-attempt-unresolved"
            latest = max([row["reserved_at"] for row in old_rows] or [0])
            db.execute("INSERT INTO state VALUES(1,?,?,?,?,?,?,?,?)",
                       (json.dumps(marker_data, sort_keys=True), old["identity"], len(old_rows),
                        pause, max(old["next_allowed"], latest + PACE_MICROS), old["windows"], created,
                        int(pause == "rate-metadata")))
            # Both databases use rollback journals on one local filesystem;
            # SQLite's super-journal makes retirement + grant creation atomic.
            db.execute("UPDATE legacy.state SET halted=1 WHERE id=1")
            db.execute("""CREATE TABLE legacy.local_evaluation_binding (
                id INTEGER PRIMARY KEY CHECK(id=1), grant_id TEXT NOT NULL,
                identity TEXT NOT NULL, ledger_name TEXT NOT NULL)""")
            db.execute("INSERT INTO legacy.local_evaluation_binding VALUES(1,?,?,?)",
                       (GRANT_ID, identity, path.name))
            db.commit()
            directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (sqlite3.Error, OSError, ValueError, TypeError, KeyError):
            if db is not None:
                db.rollback()
            raise BudgetError("local_evaluation_initialization_incomplete_preserve_files") from None
        finally:
            if db is not None:
                db.close()
        return cls(path, actor=actor, clock=clock)

    @contextmanager
    def _transaction(self):
        for path in (self.path, self.marker, self.legacy_path, self.legacy_marker):
            _secure(path)
        db = None
        try:
            db = sqlite3.connect(self.path.as_uri() + "?mode=rw", uri=True, timeout=15)
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA synchronous=FULL")
            db.execute("ATTACH DATABASE ? AS legacy", (self.legacy_path.as_uri() + "?mode=rw",))
            db.execute("BEGIN IMMEDIATE")
            if any(db.execute(f"PRAGMA {schema}.quick_check").fetchone()[0] != "ok"
                   for schema in ("main", "legacy")):
                raise BudgetError("corrupt_local_evaluation_ledger")
            yield db
            db.commit()
        except (sqlite3.Error, OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError):
            if db is not None:
                db.rollback()
            raise BudgetError("corrupt_or_unavailable_local_evaluation_ledger") from None
        except BaseException:
            if db is not None:
                db.rollback()
            raise
        finally:
            if db is not None:
                db.close()

    def _state(self, db):
        state = db.execute("SELECT * FROM main.state WHERE id=1").fetchone()
        if state is None or self.marker.stat().st_size > 2048:
            raise BudgetError("corrupt_local_evaluation_ledger")
        marker_text = self.marker.read_text(encoding="ascii")
        if marker_text != state["marker"]:
            raise BudgetError("local_evaluation_identity_mismatch")
        marker = json.loads(marker_text)
        if (set(marker) != {"version", "grant_id", "identity", "created", "expires", "unit_cost"}
                or marker["version"] != 1 or marker["grant_id"] != GRANT_ID
                or type(marker["created"]) is not int or marker["created"] < 0
                or marker["expires"] != marker["created"] + LIFETIME_MICROS
                or type(marker["unit_cost"]) is not int or not 0 < marker["unit_cost"] <= UNIT_COST_MICROS
                or state["pause_reason"] not in CORRECTIONS.keys() | {None}
                or state["rate_metadata_invalid"] not in {0, 1}
                or (state["rate_metadata_invalid"] and not state["pause_reason"])):
            raise BudgetError("corrupt_local_evaluation_ledger")
        old = _legacy_state(db, self.legacy_marker)
        binding = db.execute("SELECT * FROM legacy.local_evaluation_binding WHERE id=1").fetchone()
        if (not old["halted"] or old["identity"] != state["legacy_identity"]
                or binding is None or binding["grant_id"] != GRANT_ID
                or binding["identity"] != marker["identity"] or binding["ledger_name"] != self.path.name
                or db.execute("SELECT COUNT(*) FROM legacy.attempts").fetchone()[0] != state["legacy_attempts"]):
            raise BudgetError("legacy_accounting_fence_broken")
        rows = _rows(db)
        _check_rows(rows)
        return state, marker, rows

    def reserve(self, endpoint: str) -> Reservation:
        if endpoint not in {"web", "news"}:
            raise BudgetError("unclassified_endpoint")
        with self._transaction() as db:
            state, marker, rows = self._state(db)
            now = _now(self.clock)  # Recheck after acquiring both write locks.
            self._time(state, marker, now)
            if state["pause_reason"]:
                raise BudgetError("local_evaluation_paused_" + state["pause_reason"])
            if any(row["status_class"] == "pending" for row in rows):
                raise BudgetError("previous_attempt_unresolved")
            if now < state["next_allowed"]:
                raise BudgetError("shared_backoff")
            windows = json.loads(state["windows"])
            active = [window for window in windows if now < window["reset_at"]]
            for window in active:
                if window["remaining"] <= 0:
                    raise BudgetError("provider_quota_exhausted")
                window["remaining"] -= 1
            cost = sum(max(row["reserved_cost"], row["reconciled_cost"] or 0) for row in rows)
            if len(rows) >= MAX_ATTEMPTS or cost + marker["unit_cost"] > MAX_COST_MICROS:
                raise BudgetError("attempt_budget_exhausted")
            if self.actor == "automated" and sum(row["actor"] == "automated" for row in rows) >= MAX_AUTOMATED_ATTEMPTS:
                raise BudgetError("automated_attempt_budget_exhausted")
            cur = db.execute("INSERT INTO main.attempts(endpoint,actor,reserved_at,reserved_cost) VALUES(?,?,?,?)",
                             (endpoint, self.actor, now, marker["unit_cost"]))
            db.execute("UPDATE main.state SET next_allowed=?,windows=?,last_observed=? WHERE id=1",
                       (now + PACE_MICROS, json.dumps(active), now))
            return Reservation(cur.lastrowid, endpoint, marker["unit_cost"])

    @staticmethod
    def _time(state, marker, now):
        if now < marker["created"] or now < state["last_observed"]:
            raise BudgetError("clock_moved_backwards")
        if now >= marker["expires"]:
            raise BudgetError("local_evaluation_expired")

    def complete(self, reservation: Reservation, *, status_class: str,
                 http_status: int | None = None, retry_after_seconds=None,
                 rate_limit_headers: dict | None = None) -> None:
        if (status_class not in STATUSES or (http_status is not None and
                (type(http_status) is not int or not 100 <= http_status <= 599))
                or (status_class == "success" and (http_status is None or not 200 <= http_status <= 299))):
            raise BudgetError("invalid_outcome")
        with self._transaction() as db:
            state, marker, _ = self._state(db)
            now = _now(self.clock)
            headers = dict(rate_limit_headers or {})
            if retry_after_seconds is not None:
                headers["retry-after"] = str(retry_after_seconds)
            pause = _pause_for(status_class, http_status)
            invalid_metadata = False
            try:
                windows, next_allowed = rate_windows(headers, now)
            except BudgetError:
                windows, next_allowed, invalid_metadata = [], now, True
                pause = pause or "rate-metadata"
            row = db.execute("SELECT * FROM main.attempts WHERE id=?", (reservation.id,)).fetchone()
            if (row is None or row["endpoint"] != reservation.endpoint
                    or row["reserved_cost"] != reservation.reserved_micros or row["status_class"] != "pending"):
                raise BudgetError("invalid_or_completed_reservation")
            db.execute("UPDATE main.attempts SET status_class=?,http_status=? WHERE id=?",
                       (status_class, http_status, reservation.id))
            db.execute("UPDATE main.state SET pause_reason=COALESCE(?,pause_reason),next_allowed=MAX(next_allowed,?),windows=?,last_observed=MAX(last_observed,?),rate_metadata_invalid=MAX(rate_metadata_invalid,?) WHERE id=1",
                       (pause, next_allowed, json.dumps(windows) if windows else state["windows"], now, int(invalid_metadata)))

    def resume(self, *, correction: str) -> dict:
        """Operator-only acknowledgement of an actual offline correction.

        The caller must explain/perform the correction; this method grants no
        extra requests, time or money and cannot reopen an expired grant.
        """
        with self._transaction() as db:
            state, marker, rows = self._state(db)
            now = _now(self.clock)
            self._time(state, marker, now)
            pending = any(row["status_class"] == "pending" for row in rows)
            reason = state["pause_reason"] or ("previous-attempt-unresolved" if pending else None)
            if reason is None or correction not in CORRECTIONS[reason]:
                raise BudgetError("matching_offline_correction_required")
            if pending:
                if correction != "transport-reviewed":
                    raise BudgetError("previous_attempt_unresolved")
                db.execute("UPDATE main.attempts SET status_class='unknown' WHERE status_class='pending'")
            db.execute("INSERT INTO main.corrections(corrected_at,reason,correction) VALUES(?,?,?)", (now, reason, correction))
            metadata_pending = bool(state["rate_metadata_invalid"]) and correction != "rate-metadata-corrected"
            db.execute("UPDATE main.state SET pause_reason=?,last_observed=?,rate_metadata_invalid=? WHERE id=1",
                       ("rate-metadata" if metadata_pending else None, now, int(metadata_pending)))
        return self.snapshot()

    def reconcile(self, reservation_id: int, billed_micros: int) -> None:
        if type(billed_micros) is not int or billed_micros < 0:
            raise BudgetError("invalid_reconciliation")
        with self._transaction() as db:
            self._state(db)
            row = db.execute("SELECT * FROM main.attempts WHERE id=?", (reservation_id,)).fetchone()
            if row is None or row["status_class"] == "pending" or row["reconciled_cost"] is not None:
                raise BudgetError("invalid_reconciliation")
            db.execute("UPDATE main.attempts SET reconciled_cost=? WHERE id=?", (billed_micros, reservation_id))

    def snapshot(self) -> dict:
        with self._transaction() as db:
            state, marker, rows = self._state(db)
            now = _now(self.clock)
            automated = sum(row["actor"] == "automated" for row in rows)
            successes = [row for row in rows if row["http_status"] is not None and 200 <= row["http_status"] <= 299]
            unknown = [row for row in rows if row["http_status"] is None]
            reserved = sum(row["reserved_cost"] for row in rows)
            used = sum(max(row["reserved_cost"], row["reconciled_cost"] or 0) for row in rows)
            pending = any(row["status_class"] == "pending" for row in rows)
            pause = state["pause_reason"] or ("previous-attempt-unresolved" if pending else None)
            endpoint_outcomes = {}
            for kind in ("web", "news"):
                endpoint_rows = [row for row in rows if row["endpoint"] == kind]
                endpoint_outcomes[kind] = dict(attempts=len(endpoint_rows),
                    http_successes=sum(row["http_status"] is not None and 200 <= row["http_status"] <= 299 for row in endpoint_rows),
                    schema_successes=sum(row["status_class"] == "success" for row in endpoint_rows),
                    latest_schema_reserved_at=max((row["reserved_at"] for row in endpoint_rows
                        if row["status_class"] == "success"), default=None),
                    latest_http_status=endpoint_rows[-1]["http_status"] if endpoint_rows else None,
                    latest_status=endpoint_rows[-1]["status_class"] if endpoint_rows else None)
            complete = all(row["reconciled_cost"] is not None for row in rows)
            # Observing expiry is durable, so rolling the wall clock backwards
            # after a status check cannot reopen previously expired capacity.
            db.execute("UPDATE main.state SET last_observed=MAX(last_observed,?) WHERE id=1", (now,))
            return dict(profile="local-live", environment="local", grant_id=GRANT_ID,
                approval_reference=GRANT_ID, actor=self.actor, attempts=len(rows),
                automated_attempts=automated, manual_attempts=len(rows) - automated,
                old_smoke_attempts=state["legacy_attempts"], max_attempts=MAX_ATTEMPTS,
                max_automated_attempts=MAX_AUTOMATED_ATTEMPTS, global_cap_micros=MAX_COST_MICROS,
                unit_cost_micros=marker["unit_cost"], created_utc_micros=marker["created"],
                expires_utc_micros=marker["expires"], expired=now >= marker["expires"],
                remaining_attempts=max(0, min(MAX_ATTEMPTS - len(rows), (MAX_COST_MICROS - used) // marker["unit_cost"])),
                remaining_automated_attempts=max(0, min(MAX_AUTOMATED_ATTEMPTS - automated, MAX_ATTEMPTS - len(rows), (MAX_COST_MICROS - used) // marker["unit_cost"])),
                remaining_micros=max(0, MAX_COST_MICROS - used), conservative_reserved_micros=reserved,
                cap_consumed_micros=used, confirmed_successes=len(successes),
                schema_successes=sum(row["status_class"] == "success" for row in rows),
                estimated_success_cost_micros=sum(row["reserved_cost"] for row in successes),
                unknown_outcomes=len(unknown), unknown_reserved_micros=sum(row["reserved_cost"] for row in unknown),
                reconciled_attempts=sum(row["reconciled_cost"] is not None for row in rows),
                reconciled_billed_requests=sum((row["reconciled_cost"] or 0) > 0 for row in rows),
                reconciled_billed_micros=sum(row["reconciled_cost"] or 0 for row in rows),
                billing_reconciliation_complete=complete,
                actual_reconciled_micros=sum(row["reconciled_cost"] or 0 for row in rows) if complete else None,
                halted=bool(pause), pause_reason=pause, next_allowed_utc_micros=state["next_allowed"],
                endpoint_attempts={kind: sum(row["endpoint"] == kind for row in rows) for kind in ("web", "news")},
                endpoint_outcomes=endpoint_outcomes,
                verified_web=any(row["endpoint"] == "web" and row["status_class"] == "success" for row in rows),
                verified_news=any(row["endpoint"] == "news" and row["status_class"] == "success" for row in rows))
