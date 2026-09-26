"""Durable local paid-attempt ceilings. No query, URL, IP or credentials here.

Reserve commits before network dispatch. Attempt reservations are never refunded.
SQLite is a local-only implementation; production requires an approved shared
transactional store and explicit authorization, neither inferred by this module.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import time
import uuid

from .secrets import SecretError, validate_local_path

MICROS_PER_SECOND = 1_000_000
LIST_RATE_MICROS = 5_000  # USD: $5 / 1,000 successful calls, reviewed 2026-09-26.
STATUSES = frozenset({"success", "auth_error", "rate_limited", "http_error",
                      "transport_error", "malformed_response", "unknown"})


def utc_microseconds() -> int:
    return time.time_ns() // 1_000


class BudgetError(RuntimeError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class Reservation:
    id: int
    endpoint: str
    reserved_micros: int


def default_ledger_path(repo_root: Path) -> Path:
    # The common Git directory shares the one allowance across all worktrees.
    # It is independent of source checkout, content caches and build directories.
    root = Path(repo_root).absolute()
    try:
        result = subprocess.run(["git", "-C", str(root), "rev-parse", "--git-common-dir"],
                                capture_output=True, text=True, check=True, timeout=5)
        common = Path(result.stdout.strip())
        if not common.is_absolute():
            common = root / common
        if not result.stdout.strip() or ".." in common.parts:
            raise ValueError()
    except (OSError, ValueError, subprocess.SubprocessError):
        raise BudgetError("repository_accounting_location_unavailable") from None
    return common / "wingman-operations" / "brave_budget.sqlite3"


def _now(clock) -> int:
    value = clock()
    if type(value) is not int or value < 0:
        raise BudgetError("invalid_clock")
    return value


def _secure(path: Path, require_file: bool = True) -> Path:
    try:
        return validate_local_path(path, require_file=require_file)
    except SecretError:
        raise BudgetError("unsafe_or_missing_ledger") from None


def _number(value: str) -> float:
    if not re.fullmatch(r"\d+(?:\.\d+)?", value.strip()):
        raise BudgetError("invalid_rate_metadata")
    number = float(value)
    if not math.isfinite(number) or number > 1_000_000_000:
        raise BudgetError("invalid_rate_metadata")
    return number


def rate_windows(headers: dict, now: int) -> tuple[list[dict], int]:
    """Parse each returned Brave quota window and Retry-After, fail closed.

    Brave represents parallel windows as comma-separated limit/remaining/reset
    fields and policy entries of the form `20;w=1`. Unknown metadata is never
    treated as extra quota. Stored reset instants use integer UTC microseconds.
    """
    lowered = {str(key).lower(): str(value) for key, value in headers.items()}
    next_allowed = now
    retry = lowered.get("retry-after")
    if retry is not None:
        try:
            delay = _number(retry)
            next_allowed = now + math.ceil(delay * MICROS_PER_SECOND)
        except BudgetError:
            try:
                parsed = parsedate_to_datetime(retry)
                if parsed.tzinfo is None:
                    raise ValueError()
                next_allowed = max(now, int(parsed.timestamp() * MICROS_PER_SECOND))
            except (ValueError, TypeError, OverflowError):
                raise BudgetError("invalid_rate_metadata") from None
    names = ["x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset"]
    present = [name in lowered for name in names]
    if not any(present) and "x-ratelimit-policy" not in lowered:
        return [], next_allowed
    if not all(present):
        raise BudgetError("invalid_rate_metadata")
    fields = [[_number(v) for v in lowered[name].split(",")] for name in names]
    size = len(fields[0])
    if not 1 <= size <= 16 or any(len(field) != size for field in fields):
        raise BudgetError("invalid_rate_metadata")
    periods = None
    if "x-ratelimit-policy" in lowered:
        policies = lowered["x-ratelimit-policy"].split(",")
        if len(policies) != size:
            raise BudgetError("invalid_rate_metadata")
        periods = []
        for i, policy in enumerate(policies):
            match = re.fullmatch(r"\s*(\d+)\s*;\s*w=(\d+)\s*", policy)
            if not match or int(match[1]) != fields[0][i] or int(match[2]) <= 0:
                raise BudgetError("invalid_rate_metadata")
            periods.append(int(match[2]))
    windows = []
    for i, (limit, remaining, reset) in enumerate(zip(*fields)):
        if (limit < 1 or remaining < 0 or remaining > limit
                or not limit.is_integer() or not remaining.is_integer()):
            raise BudgetError("invalid_rate_metadata")
        windows.append({"limit": int(limit), "remaining": int(remaining),
                        "reset_at": now + math.ceil(reset * MICROS_PER_SECOND),
                        "period_seconds": periods[i] if periods else None})
    return windows, next_allowed


class BudgetLedger:
    def __init__(self, path: Path, *, environment: str = "local", clock=utc_microseconds):
        if environment != "local":
            raise BudgetError("production_requires_shared_ledger")
        self.path = Path(path).absolute()
        self.marker = self.path.with_name(self.path.name + ".initialized")
        self.clock = clock
        # Opening never creates a file or initializes an allowance.
        with self._transaction() as db:
            self._state(db)

    @classmethod
    def initialize_smoke(cls, path: Path, *, clock=utc_microseconds):
        return cls._initialize(path, profile="smoke", approval="launcher-v2-two-request-smoke",
                               cap=10_000, unit=LIST_RATE_MICROS,
                               caps={"web": 1, "news": 1}, clock=clock)

    @classmethod
    def initialize_approved(cls, path: Path, *, approval_reference: str,
                            global_cap_micros: int, endpoint_daily_caps: dict,
                            unit_cost_micros: int = LIST_RATE_MICROS,
                            environment: str = "local", clock=utc_microseconds):
        """Operator-only entry, after a new explicit owner spending approval.

        A reference string is an audit pointer, not proof that approval exists.
        Do not expose this function through any public or consumer API.
        """
        if environment != "local":
            raise BudgetError("production_requires_shared_ledger")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,79}", approval_reference or ""):
            raise BudgetError("approval_reference_required")
        if (type(global_cap_micros) is not int or global_cap_micros < 0
                or type(unit_cost_micros) is not int or unit_cost_micros <= 0
                or set(endpoint_daily_caps) != {"web", "news"}
                or any(type(v) is not int or v < 0 for v in endpoint_daily_caps.values())):
            raise BudgetError("invalid_budget")
        return cls._initialize(path, profile="approved-local", approval=approval_reference,
                               cap=global_cap_micros, unit=unit_cost_micros,
                               caps=endpoint_daily_caps, clock=clock)

    @classmethod
    def _initialize(cls, path, *, profile, approval, cap, unit, caps, clock):
        path = Path(path).absolute()
        # Only an explicit initialization call may create the operations directory.
        if not path.parent.exists():
            _secure(path.parent.parent / "unused-path-validation", False)
            path.parent.mkdir(mode=0o700)
        _secure(path, False)
        marker = path.with_name(path.name + ".initialized")
        _secure(marker, False)
        identity = uuid.uuid4().hex
        created = _now(clock)
        try:
            # Marker first: a crash/deletion never silently replenishes the budget.
            fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "w") as stream:
                stream.write(identity)
                stream.flush()
                os.fsync(stream.fileno())
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
            os.close(fd)
            db = sqlite3.connect(path)
            try:
                db.execute("PRAGMA journal_mode=DELETE")
                db.execute("PRAGMA synchronous=FULL")
                db.executescript("""
                    CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL,
                        identity TEXT NOT NULL, profile TEXT NOT NULL, approval TEXT NOT NULL,
                        global_cap INTEGER NOT NULL, unit_cost INTEGER NOT NULL, caps TEXT NOT NULL,
                        created INTEGER NOT NULL, halted INTEGER NOT NULL DEFAULT 0,
                        next_allowed INTEGER NOT NULL DEFAULT 0, windows TEXT NOT NULL DEFAULT '[]');
                    CREATE TABLE attempts (id INTEGER PRIMARY KEY, endpoint TEXT NOT NULL,
                        environment TEXT NOT NULL CHECK(environment='local'), date_bucket TEXT NOT NULL,
                        reserved_at INTEGER NOT NULL, reserved_cost INTEGER NOT NULL,
                        status_class TEXT NOT NULL DEFAULT 'pending', http_status INTEGER,
                        reconciled_cost INTEGER);
                """)
                db.execute("INSERT INTO state(id,version,identity,profile,approval,global_cap,unit_cost,caps,created) VALUES(1,1,?,?,?,?,?,?,?)",
                           (identity, profile, approval, cap, unit, json.dumps(caps), created))
                db.commit()
            finally:
                db.close()
            directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except (OSError, sqlite3.Error):
            raise BudgetError("initialization_refused_preserve_existing_ledger") from None
        return cls(path, clock=clock)

    @contextmanager
    def _transaction(self):
        _secure(self.path)
        _secure(self.marker)
        db = None
        try:
            db = sqlite3.connect(self.path.as_uri() + "?mode=rw", uri=True, timeout=15)
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                raise BudgetError("corrupt_ledger")
            yield db
            db.commit()
        except (sqlite3.Error, ValueError, KeyError, TypeError, OSError):
            if db is not None:
                db.rollback()
            raise BudgetError("corrupt_or_unavailable_ledger") from None
        except BaseException:
            if db is not None:
                db.rollback()
            raise
        finally:
            if db is not None:
                db.close()

    def _state(self, db):
        state = db.execute("SELECT * FROM state WHERE id=1").fetchone()
        if state is None or state["version"] != 1:
            raise BudgetError("corrupt_ledger")
        # This contains random nonsecret installation identity only, never a key.
        if self.marker.read_text(encoding="ascii") != state["identity"]:
            raise BudgetError("ledger_identity_mismatch")
        caps = json.loads(state["caps"])
        if (set(caps) != {"web", "news"} or any(type(v) is not int or v < 0 for v in caps.values())
                or state["global_cap"] < 0 or state["unit_cost"] <= 0
                or state["profile"] not in {"smoke", "approved-local"}):
            raise BudgetError("corrupt_ledger")
        if state["profile"] == "smoke" and (caps != {"web": 1, "news": 1}
                or state["global_cap"] != 10_000 or state["unit_cost"] != LIST_RATE_MICROS):
            raise BudgetError("smoke_allowance_modified")
        return state, caps

    def reserve(self, endpoint: str) -> Reservation:
        if endpoint not in {"web", "news"}:
            raise BudgetError("unclassified_endpoint")
        now = _now(self.clock)
        day = datetime.fromtimestamp(now / MICROS_PER_SECOND, timezone.utc).date().isoformat()
        with self._transaction() as db:
            state, caps = self._state(db)
            if state["halted"]:
                raise BudgetError("operator_intervention_required")
            if db.execute("SELECT COUNT(*) FROM attempts WHERE status_class='pending'").fetchone()[0]:
                raise BudgetError("previous_attempt_unresolved")
            if now < state["next_allowed"]:
                raise BudgetError("shared_backoff")
            windows = json.loads(state["windows"])
            for window in windows:
                if now < window["reset_at"]:
                    if window["remaining"] <= 0:
                        raise BudgetError("provider_quota_exhausted")
                    window["remaining"] -= 1
            windows = [window for window in windows if now < window["reset_at"]]
            params = (endpoint,) if state["profile"] == "smoke" else (endpoint, day)
            condition = "endpoint=?" if state["profile"] == "smoke" else "endpoint=? AND date_bucket=?"
            count = db.execute("SELECT COUNT(*) FROM attempts WHERE " + condition, params).fetchone()[0]
            spent = db.execute("SELECT COALESCE(SUM(reserved_cost),0) FROM attempts").fetchone()[0]
            if count >= caps[endpoint] or spent + state["unit_cost"] > state["global_cap"]:
                raise BudgetError("attempt_budget_exhausted")
            cursor = db.execute("INSERT INTO attempts(endpoint,environment,date_bucket,reserved_at,reserved_cost) VALUES(?,'local',?,?,?)",
                                (endpoint, day, now, state["unit_cost"]))
            db.execute("UPDATE state SET next_allowed=?,windows=? WHERE id=1",
                       (now + MICROS_PER_SECOND, json.dumps(windows)))
            return Reservation(cursor.lastrowid, endpoint, state["unit_cost"])

    def complete(self, reservation: Reservation, *, status_class: str,
                 http_status: int | None = None, retry_after_seconds: float | None = None,
                 rate_limit_headers: dict | None = None) -> None:
        if status_class not in STATUSES or (http_status is not None and
                (type(http_status) is not int or not 100 <= http_status <= 599)):
            raise BudgetError("invalid_outcome")
        if status_class == "success" and (http_status is None or not 200 <= http_status <= 299):
            raise BudgetError("success_requires_received_2xx")
        now = _now(self.clock)
        headers = dict(rate_limit_headers or {})
        if retry_after_seconds is not None:
            headers["retry-after"] = str(retry_after_seconds)
        invalid_metadata = False
        try:
            windows, next_allowed = rate_windows(headers, now)
        except BudgetError:
            windows, next_allowed, invalid_metadata = [], now, True
        with self._transaction() as db:
            state, _ = self._state(db)
            row = db.execute("SELECT * FROM attempts WHERE id=?", (reservation.id,)).fetchone()
            if (row is None or row["endpoint"] != reservation.endpoint
                    or row["reserved_cost"] != reservation.reserved_micros
                    or row["status_class"] != "pending"):
                raise BudgetError("invalid_or_completed_reservation")
            db.execute("UPDATE attempts SET status_class=?,http_status=? WHERE id=?",
                       (status_class, http_status, reservation.id))
            stop = invalid_metadata or status_class == "auth_error" or (
                state["profile"] == "smoke" and status_class != "success")
            # Empty headers preserve previously observed provider windows.
            saved_windows = json.dumps(windows) if windows else state["windows"]
            db.execute("UPDATE state SET halted=MAX(halted,?),next_allowed=MAX(next_allowed,?),windows=? WHERE id=1",
                       (int(stop), next_allowed, saved_windows))

    def reconcile(self, reservation_id: int, billed_micros: int) -> None:
        """Private operator reconciliation; never refunds reserved attempt capacity."""
        if type(billed_micros) is not int or billed_micros < 0:
            raise BudgetError("invalid_reconciliation")
        with self._transaction() as db:
            self._state(db)
            row = db.execute("SELECT status_class,reconciled_cost FROM attempts WHERE id=?", (reservation_id,)).fetchone()
            if row is None or row[0] == "pending" or row[1] is not None:
                raise BudgetError("invalid_reconciliation")
            db.execute("UPDATE attempts SET reconciled_cost=? WHERE id=?", (billed_micros, reservation_id))

    def snapshot(self) -> dict:
        with self._transaction() as db:
            state, caps = self._state(db)
            rows = db.execute("SELECT endpoint,status_class,http_status,reserved_cost,reconciled_cost FROM attempts").fetchall()
            successes = [row for row in rows if row["http_status"] is not None and 200 <= row["http_status"] <= 299]
            unknown = [row for row in rows if row["http_status"] is None]
            return {"profile": state["profile"], "environment": "local", "attempts": len(rows),
                    "endpoint_attempts": {kind: sum(row["endpoint"] == kind for row in rows) for kind in caps},
                    "endpoint_caps": caps, "global_cap_micros": state["global_cap"],
                    "conservative_reserved_micros": sum(row["reserved_cost"] for row in rows),
                    "confirmed_successes": len(successes),
                    "schema_successes": sum(row["status_class"] == "success" for row in rows),
                    "estimated_success_cost_micros": sum(row["reserved_cost"] for row in successes),
                    "unknown_outcomes": len(unknown),
                    "unknown_reserved_micros": sum(row["reserved_cost"] for row in unknown),
                    "reconciled_attempts": sum(row["reconciled_cost"] is not None for row in rows),
                    "reconciled_billed_micros": sum(row["reconciled_cost"] or 0 for row in rows),
                    "halted": bool(state["halted"]), "next_allowed_utc_micros": state["next_allowed"]}
