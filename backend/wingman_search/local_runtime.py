"""Explicit, loopback-only live evaluation; independent of production approval.

Constructing the application never initializes an allowance or calls Brave.
Only a user submission can reserve and dispatch an attempt. Actor attribution is
fixed when the server starts, not accepted from the HTTP request.
"""
import os
from pathlib import Path

from .budget import BudgetError
from .gateway import SearchApplication
from .provider import BraveProvider
from .contracts import SearchError
from .secrets import SecretError, default_secret_path, load_secret, secret_status


class LocalRuntimeError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


DIAGNOSTICS = {
    'credential-unconfigured': 'Run python3 backend/setup_brave_secret.py from the repository, then start local live mode again.',
    'credential-invalid': 'The dedicated local credential configuration is invalid or unsafe. Use the hidden setup utility.',
    'allowance-uninitialized': 'Run PYTHONPATH=backend python3 -m wingman_search initialize-local once for the existing authorized grant.',
    'allowance-unavailable': 'Local allowance accounting is unavailable. Inspect status-local; do not replace or reset the ledger.',
}
ACCOUNTING_FIELDS = frozenset({
    'grant_id', 'profile', 'attempts', 'automated_attempts', 'manual_attempts',
    'remaining_attempts', 'remaining_automated_attempts', 'conservative_reserved_micros',
    'remaining_micros', 'expires_utc_micros', 'halted', 'pause_reason',
    'next_allowed_utc_micros', 'endpoint_attempts', 'verified_web', 'verified_news',
    'old_smoke_attempts', 'actual_billed_micros', 'reconciled_billed_requests',
    'unit_cost_micros', 'max_attempts', 'max_micros', 'max_automated_attempts',
    'confirmed_successes', 'unknown_attempts', 'pending_attempts', 'initialized_utc_micros',
    'global_cap_micros', 'created_utc_micros', 'expired', 'cap_consumed_micros',
    'estimated_success_cost_micros', 'unknown_outcomes', 'unknown_reserved_micros',
    'reconciled_billed_micros', 'all_attempts_reconciled', 'unreconciled_attempts',
    'confirmed_successful_requests', 'actual_billing_known', 'actual_billed_requests',
    'schema_successes', 'reconciled_attempts', 'billing_reconciliation_complete',
    'endpoint_outcomes', 'actual_reconciled_micros',
})


def _ledger_type():
    from .local_budget import LocalEvaluationLedger
    return LocalEvaluationLedger


def credential_identity(path):
    # Metadata is used only to detect replacement, never as a credential hash.
    info = os.stat(path, follow_symlinks=False)
    return (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns, info.st_size)


def local_status(repo_root, *, actor='manual', ledger=None, ledger_factory=None):
    """No key content read, provider request, or spending reservation.

    The ledger may persist an observed clock to enforce expiry after rollback.
    """
    from .local_budget import default_local_ledger_path
    root = Path(repo_root).absolute()
    credential_path = default_secret_path(root)
    credential = secret_status(credential_path, root).replace('_', '-')
    try:
        credential_modified = credential_identity(credential_path)[2] // 1000
    except OSError:
        credential_modified = None
    accounting, accounting_status = None, 'available'
    try:
        if ledger is None:
            ledger_path = default_local_ledger_path(root)
            marker_path = ledger_path.with_name(ledger_path.name + '.initialized')
            if (ledger_factory is None and not os.path.lexists(ledger_path)
                    and not os.path.lexists(marker_path)):
                accounting_status = 'uninitialized'
                raise BudgetError('uninitialized')
            ledger = (ledger_factory or _ledger_type())(ledger_path, actor=actor)
        raw = ledger.snapshot()
        accounting = {key: raw[key] for key in ACCOUNTING_FIELDS if key in raw}
    except (BudgetError, OSError):
        if accounting_status != 'uninitialized':
            accounting_status = 'unavailable'
    successes = (accounting or {}).get('endpoint_outcomes', {})
    def verified(kind):
        timestamp = successes.get(kind, {}).get('latest_schema_reserved_at')
        return (credential == 'configured-unverified' and credential_modified is not None
                and type(timestamp) is int and timestamp >= credential_modified)
    verified_web, verified_news = verified('web'), verified('news')
    if accounting is not None:
        # The ledger's historical verification flags belong to the grant. The
        # exposed flags always refer to the currently configured credential.
        accounting['verified_web'], accounting['verified_news'] = verified_web, verified_news
    credential_label = ('verified-web-and-news' if verified_web and verified_news
                        else 'verified-web' if verified_web
                        else 'verified-news' if verified_news else credential)
    return {
        'mode': 'local-live', 'provider': 'brave', 'localOnly': True,
        'actor': actor, 'credentialStatus': credential_label,
        'verifiedWeb': verified_web, 'verifiedNews': verified_news,
        'accountingStatus': accounting_status, 'accounting': accounting,
        'resultCount': 10, 'automaticRetries': False, 'liveAds': False,
    }


def create_local_search_application(repo_root, *, actor='manual', ledger_factory=None,
                                    secret_loader=load_secret, provider_factory=BraveProvider,
                                    transport=None):
    from .local_budget import default_local_ledger_path
    if actor not in ('manual', 'automated'):
        raise LocalRuntimeError('invalid-actor')
    root = Path(repo_root).absolute()
    path = default_secret_path(root)
    state = secret_status(path, root)
    if state == 'unconfigured':
        raise LocalRuntimeError('credential-unconfigured')
    if state != 'configured_unverified':
        raise LocalRuntimeError('credential-invalid')
    ledger_path = default_local_ledger_path(root)
    marker_path = ledger_path.with_name(ledger_path.name + '.initialized')
    if (ledger_factory is None and not os.path.lexists(ledger_path)
            and not os.path.lexists(marker_path)):
        raise LocalRuntimeError('allowance-uninitialized')
    try:
        ledger = (ledger_factory or _ledger_type())(ledger_path, actor=actor)
        ledger.snapshot()  # Fail closed before loading the credential.
    except (BudgetError, OSError):
        raise LocalRuntimeError('allowance-unavailable') from None
    try:
        identity = credential_identity(path)
        key = secret_loader(path, root)
        if credential_identity(path) != identity:
            raise SecretError('credential_changed_during_load')
    except (SecretError, OSError):
        raise LocalRuntimeError('credential-invalid') from None
    provider = provider_factory(ledger, key, transport=transport, default_count=10)
    def unchanged_credential():
        try:
            if credential_identity(path) != identity:
                raise OSError()
        except OSError:
            raise SearchError('configuration-required', 503) from None
    provider.before_request = unchanged_credential
    app = SearchApplication(provider, mode='local-live')
    app.local_status = lambda: local_status(root, actor=actor, ledger=ledger)
    return app
