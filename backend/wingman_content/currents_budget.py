"""Durable Currents attempt accounting, shared lease and scheduler state.

This object/database is deliberately separate from the disposable content cache.
Mutators perform no network I/O; a reserved attempt is never refunded.
"""
import copy
import json
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

HARD_CAP = 150
QUOTA_RESERVE = 5
LEASE_SECONDS = 60  # Transport has a strictly shorter 25-second deadline.
MAX_LEDGER_BYTES = 512 * 1024


def utcnow():
    return datetime.now(timezone.utc)


def stamp(now):
    return now.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def moment(value):
    if not isinstance(value, str):
        raise ValueError('invalid ledger timestamp')
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('naive ledger timestamp')
    return parsed.astimezone(timezone.utc)


def tomorrow(now):
    return (now.astimezone(timezone.utc) + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)


class BudgetError(Exception):
    """Only fixed, secret-free reason codes may escape the request gateway."""
    def __init__(self, reason, attempted=False):
        super().__init__(reason)
        self.reason = reason
        self.attempted = attempted


def _initial(now):
    return {'schemaVersion': 1, 'createdAt': stamp(now), 'day': now.astimezone(timezone.utc).date().isoformat(),
            'attempts': 0, 'supplements': 0, 'hardCap': HARD_CAP, 'effectiveCap': HARD_CAP,
            'providerLimit': None, 'providerRemaining': None, 'providerObservedAt': None,
            'lease': None, 'fence': 0, 'spacingUntil': None, 'pauseUntil': None,
            'pauseReason': None, 'credentialRevision': 0, 'authAttempted': False,
            'authStatus': None, 'jobs': {}, 'metadata': {}, 'recentAttempts': [], 'history': []}


def _validate(state):
    def require(valid):
        if not valid:
            raise ValueError('invalid ledger')
    try:
        require(isinstance(state, dict) and state['schemaVersion'] == 1)
        moment(state['createdAt'])
        datetime.strptime(state['day'], '%Y-%m-%d')
        for key in ('attempts', 'supplements', 'hardCap', 'effectiveCap', 'fence', 'credentialRevision'):
            require(type(state[key]) is int and state[key] >= 0)
        require(0 <= state['effectiveCap'] <= state['hardCap'] <= HARD_CAP)
        require(state['attempts'] <= HARD_CAP and state['supplements'] <= 12)
        for key in ('providerLimit', 'providerRemaining'):
            require(state[key] is None or (type(state[key]) is int and 0 <= state[key] <= 999999999))
        require(type(state['authAttempted']) is bool)
        require(state['authStatus'] in (None, 'pending', 'ok', 'failed'))
        require(state['pauseReason'] in (None, 'authentication', 'quota'))
        for key in ('jobs', 'metadata'):
            require(isinstance(state[key], dict))
        for key in ('recentAttempts', 'history'):
            require(isinstance(state[key], list))
        for value in state['jobs'].values():
            require(isinstance(value, dict))
            moment(value['nextDue'])
            require(type(value.get('failures', 0)) is int and 0 <= value.get('failures', 0) <= 12)
            require(type(value.get('held', False)) is bool)
        lease = state['lease']
        if lease is not None:
            require(isinstance(lease['token'], str) and type(lease['fence']) is int)
            moment(lease['expiresAt'])
        for key in ('pauseUntil', 'spacingUntil', 'providerObservedAt'):
            if state.get(key) is not None:
                moment(state[key])
        require(len(state['recentAttempts']) == state['attempts'])
        for attempt in state['recentAttempts']:
            require(isinstance(attempt, dict) and isinstance(attempt['slot'], str))
            require(moment(attempt['at']).date().isoformat() == state['day'])
            require(type(attempt.get('supplement', False)) is bool)
        require(len({attempt['slot'] for attempt in state['recentAttempts']}) == state['attempts'])
        require(sum(attempt.get('supplement', False) for attempt in state['recentAttempts']) == state['supplements'])
        require(len(json.dumps(state).encode()) <= MAX_LEDGER_BYTES)
    except (KeyError, ValueError, TypeError, OverflowError):
        raise BudgetError('ledger-corrupt') from None
    return state


def _roll(state, now):
    day = now.astimezone(timezone.utc).date().isoformat()
    if day < state['day']:
        raise BudgetError('clock-regressed')
    if day > state['day']:
        state['history'] = (state['history'] + [{'day': state['day'], 'attempts': state['attempts'],
                                               'supplements': state['supplements']}])[-14:]
        state.update(day=day, attempts=0, supplements=0, providerRemaining=None,
                     providerObservedAt=None, recentAttempts=[])
        # Keep a known smaller subscription cap after UTC rollover.
        state['effectiveCap'] = min(state['hardCap'], max(0, state['providerLimit'] - QUOTA_RESERVE)
                                    if state['providerLimit'] is not None else state['hardCap'])
    return state


class Ledger:
    def diagnostics(self, now=None):
        now = now or utcnow()
        def inspect(state):
            _roll(state, now)
            return copy.deepcopy(state)
        return self.update(inspect)

    def reserve(self, job_id, path, params, now, *, next_due, supplement=False,
                allow_auth=False, spacing_seconds=3):
        token = uuid.uuid4().hex
        def reserve(state):
            _roll(state, now)
            if state['pauseReason'] == 'authentication' and not allow_auth:
                raise BudgetError('authentication-paused')
            if state['pauseUntil'] and moment(state['pauseUntil']) > now and not allow_auth:
                raise BudgetError('provider-wait')
            lease = state['lease']
            if lease and moment(lease['expiresAt']) > now:
                raise BudgetError('lease-busy')
            if state['spacingUntil'] and moment(state['spacingUntil']) > now:
                raise BudgetError('spacing-wait')
            if state['attempts'] >= state['effectiveCap']:
                raise BudgetError('local-budget-exhausted')
            if state['providerRemaining'] is not None and state['providerRemaining'] <= QUOTA_RESERVE:
                raise BudgetError('provider-quota-reserve')
            if supplement and (state['supplements'] >= 12 or
                               state['effectiveCap'] - state['attempts'] <= 10):
                raise BudgetError('supplement-budget-reserve')
            job = state['jobs'].setdefault(job_id, {'nextDue': stamp(now), 'failures': 0})
            if job.get('held'):
                raise BudgetError('query-held')
            if moment(job['nextDue']) > now:
                raise BudgetError('not-due')
            if path == '/v1/auth':
                if state['authAttempted']:
                    raise BudgetError('auth-already-attempted')
                # The setup marker and charged reservation commit together.
                # Lease/quota/storage deferral never labels an unchecked key bad.
                state.update(authAttempted=True, authStatus='pending')
            slot = job_id + ':' + job['nextDue']
            state['attempts'] += 1
            if supplement:
                state['supplements'] += 1
            # Conservative remaining estimate; actual headers update it on completion.
            if state['providerRemaining'] is not None:
                state['providerRemaining'] = max(0, state['providerRemaining'] - 1)
            state['fence'] += 1
            state['lease'] = {'token': token, 'fence': state['fence'], 'slot': slot,
                              'expiresAt': stamp(now + timedelta(seconds=LEASE_SECONDS))}
            state['spacingUntil'] = stamp(now + timedelta(seconds=spacing_seconds))
            job.update(nextDue=stamp(next_due), lastAttemptAt=stamp(now), lastSlot=slot,
                       status='attempted', parameters=params, endpoint=path)
            state['recentAttempts'].append({'slot': slot, 'job': job_id, 'at': stamp(now),
                                            'endpoint': path, 'outcome': 'uncertain', 'supplement': supplement})
            state['recentAttempts'] = state['recentAttempts'][-HARD_CAP:]
            return {'token': token, 'fence': state['fence'], 'slot': slot,
                    'job': job_id, 'day': state['day']}
        return self.update(reserve)

    def assert_lease(self, reservation, now):
        started = time.monotonic()
        def inspect(state):
            lease = state['lease']
            if (not lease or lease['token'] != reservation['token'] or
                    lease['fence'] != reservation['fence'] or moment(lease['expiresAt']) <=
                    now + timedelta(seconds=time.monotonic() - started)):
                raise BudgetError('lease-lost')
        self.update(inspect)

    def finish(self, reservation, now, *, status=None, headers=None, error=None):
        headers = {str(k).lower(): str(v) for k, v in (headers or {}).items()}
        started = time.monotonic()
        def finish(state):
            lease = state['lease']
            if (not lease or lease['token'] != reservation['token'] or lease['fence'] != reservation['fence'] or
                    moment(lease['expiresAt']) <= now + timedelta(seconds=time.monotonic() - started)):
                raise BudgetError('lease-lost')
            _roll(state, now)
            job = state['jobs'][reservation['job']]
            same_day = state['day'] == reservation['day']
            if same_day:
                for header, field in (('x-ratelimit-limit', 'providerLimit'),
                                      ('x-ratelimit-remaining', 'providerRemaining')):
                    value = headers.get(header, '')
                    if value.isdigit() and len(value) <= 9:
                        number = int(value)
                        # Never let a stale/external response increase the day's allowance.
                        state[field] = min(state[field], number) if state[field] is not None else number
                        state['providerObservedAt'] = stamp(now)
                if state['providerLimit'] is not None:
                    state['effectiveCap'] = min(state['effectiveCap'], max(0, state['providerLimit'] - QUOTA_RESERVE))
                if state['providerRemaining'] is not None:
                    state['effectiveCap'] = min(state['effectiveCap'], state['attempts'] + max(
                        0, state['providerRemaining'] - QUOTA_RESERVE))
            wait_until = retry_time(headers.get('retry-after'), now)
            reason = error or ('ok' if status == 200 else 'http-%s' % status)
            job.update(lastStatus=status, status=reason)
            if status == 400:
                job.update(held=True, status='invalid-query')
            elif status in (401, 403):
                state.update(pauseReason='authentication', authStatus='failed')
                job['status'] = 'authentication-paused'
            elif status == 429:
                if state['providerRemaining'] in (None, 0) or not wait_until:
                    wait_until = max(wait_until or now, tomorrow(now))
                state.update(pauseReason='quota', pauseUntil=stamp(wait_until))
                job['status'] = 'quota-paused'
            elif status == 200 and not error:
                job.update(failures=0, lastSuccessAt=stamp(now), status='ok')
            else:
                job['failures'] = min(12, job.get('failures', 0) + 1)
                backoff = now + timedelta(seconds=min(21600, 1800 * 2 ** (job['failures'] - 1)))
                job['nextDue'] = stamp(max(moment(job['nextDue']), backoff))
            if wait_until:
                job['nextDue'] = stamp(max(moment(job['nextDue']), wait_until))
                if status not in (400, 401, 403):
                    state['pauseUntil'] = stamp(max(moment(state['pauseUntil']) if state['pauseUntil'] else now, wait_until))
            for attempt in state['recentAttempts']:
                if attempt['slot'] == reservation['slot']:
                    attempt['outcome'] = job['status']
            state['lease'] = None
            return copy.deepcopy(job)
        return self.update(finish)


def retry_time(value, now):
    if not value:
        return None
    if value.isdigit():
        # Extremely long holds remain an indefinite operator hold, never an
        # earlier retry obtained by truncating a provider's wait instruction.
        maximum = datetime.max.replace(tzinfo=timezone.utc)
        if len(value) > 12:
            return maximum
        try:
            return now + timedelta(seconds=int(value))
        except (ValueError, OverflowError):
            return maximum
    from email.utils import parsedate_to_datetime
    try:
        return max(now, parsedate_to_datetime(value).astimezone(timezone.utc))
    except (ValueError, TypeError, OverflowError):
        return None


class LocalLedger(Ledger):
    """SQLite serializes independent local processes, including after restart.

    For multiple service instances use GCSLedger, not ephemeral instance disks.
    """
    def __init__(self, path):
        self.path = Path(path)

    def initialize(self, now=None):
        now = now or utcnow()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        try:
            # O_EXCL prevents an operator typo from resetting an established cap.
            import os
            descriptor = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(descriptor)
        except FileExistsError:
            raise BudgetError('ledger-already-exists') from None
        try:
            with sqlite3.connect(self.path) as db:
                db.execute('PRAGMA synchronous=FULL')
                db.execute('CREATE TABLE ledger (id INTEGER PRIMARY KEY CHECK(id=1), state TEXT NOT NULL)')
                db.execute('INSERT INTO ledger VALUES (1, ?)', (json.dumps(_initial(now)),))
        except Exception:
            raise BudgetError('ledger-initialization-failed') from None
        return self.diagnostics(now)

    def update(self, mutate):
        db = None
        try:
            db = sqlite3.connect(self.path.resolve().as_uri() + '?mode=rw', uri=True, timeout=10)
            db.execute('PRAGMA synchronous=FULL')
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT state FROM ledger WHERE id=1').fetchone()
            if row is None:
                raise BudgetError('ledger-corrupt')
            state = _validate(json.loads(row[0]))
            result = mutate(state)
            _validate(state)
            db.execute('UPDATE ledger SET state=? WHERE id=1', (json.dumps(state, separators=(',', ':')),))
            db.commit()
            return result
        except BudgetError:
            raise
        except (ValueError, TypeError):
            raise BudgetError('ledger-corrupt') from None
        except Exception:
            raise BudgetError('ledger-unavailable') from None
        finally:
            if db is not None:
                db.close()


class GCSLedger(Ledger):
    """One independent private object with generation compare-and-swap.

    Retried CAS callbacks contain state changes only. The HTTP request always
    happens after a successful committed reservation, outside this loop.
    """
    def __init__(self, bucket, project, object_name='wingman-operations/currents-ledger.json', client=None):
        if not project:
            raise ValueError('Explicit CONTENT_PROJECT required')
        if client is None:
            from google.cloud import storage
            client = storage.Client(project=project)
        self.bucket = client.bucket(bucket)
        self.object_name = object_name

    def initialize(self, now=None):
        now = now or utcnow()
        try:
            self.bucket.blob(self.object_name).upload_from_string(
                json.dumps(_initial(now)), content_type='application/json',
                if_generation_match=0, timeout=10, retry=None)
        except Exception as exc:
            if getattr(exc, 'code', None) in (409, 412):
                raise BudgetError('ledger-already-exists') from None
            raise BudgetError('ledger-initialization-failed') from None
        return self.diagnostics(now)

    def update(self, mutate):
        for _ in range(12):
            try:
                blob = self.bucket.blob(self.object_name)
                blob.reload(timeout=10, retry=None)
                if blob.size > MAX_LEDGER_BYTES:
                    raise BudgetError('ledger-corrupt')
                generation = int(blob.generation)
                state = _validate(json.loads(blob.download_as_bytes(
                    if_generation_match=generation, timeout=10, retry=None)))
                result = mutate(state)
                _validate(state)
                blob.upload_from_string(json.dumps(state, separators=(',', ':')),
                                        content_type='application/json', if_generation_match=generation,
                                        timeout=10, retry=None)
                return result
            except BudgetError:
                raise
            except (ValueError, TypeError):
                raise BudgetError('ledger-corrupt') from None
            except Exception as exc:
                if getattr(exc, 'code', None) in (409, 412):
                    continue
                raise BudgetError('ledger-unavailable') from None
        raise BudgetError('ledger-contention')
