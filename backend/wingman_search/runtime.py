"""Explicit production construction. Importing this module performs no I/O.

No default project, secret, location, budget or approval is inferred. The
operator must separately initialize the authorized operations ledger. This
factory only opens it, and checks the immutable cap before loading a key.
"""
from pathlib import Path
import json
from .config import SearchConfig, ConfigurationError
from .budget import BudgetError
from .secrets import SecretError, validate_key
from .shared_budget import GCSBudgetLedger
from .provider import BraveProvider


def read_config(path):
    try:
        path = Path(path)
        if path.stat().st_size > 16384:
            raise ValueError()
        from .contracts import decode_json
        value = decode_json(path.read_bytes(), 16384)
        config = SearchConfig(**value)
        config.validate()
        return config
    except Exception:
        raise ConfigurationError('invalid_search_configuration') from None


def _secret(reference):
    client = None
    try:
        from google.cloud import secretmanager
        import google_crc32c
        client = secretmanager.SecretManagerServiceClient()
        response = client.access_secret_version(request={'name': reference}, retry=None, timeout=10)
        data = response.payload.data
        if (not isinstance(data, bytes) or not 12 <= len(data) <= 4096
                or google_crc32c.value(data) != response.payload.data_crc32c):
            raise ValueError()
        return validate_key(data.decode('ascii'))
    except Exception:
        raise SecretError('approved_secret_unavailable') from None
    finally:
        if client is not None:
            try:
                client.transport.close()
            except Exception:
                pass


def create_brave_provider(config: SearchConfig, *, ledger_factory=GCSBudgetLedger,
                          secret_loader=_secret, transport=None):
    config.validate()
    if config.profile != 'production' or config.environment != 'production':
        raise ConfigurationError('approved_production_configuration_required')
    # Constructor validates the durable marker's approval as well as every read.
    ledger = ledger_factory(project=config.shared_project, bucket=config.shared_bucket,
        object_name=config.shared_object, approval_reference=config.provider_spend_approval_reference)
    accounting = ledger.snapshot()
    if (accounting.get('global_cap_micros') != config.production_cap_micros
            or accounting.get('unit_cost_micros') != config.production_unit_cost_micros
            or accounting.get('approval_reference') != config.provider_spend_approval_reference
            or accounting.get('profile') != 'approved-production'
            or accounting.get('environment') != 'production'):
        raise BudgetError('approved_cap_mismatch')
    key = validate_key(secret_loader(config.secret_manager_reference))
    provider = BraveProvider(ledger, key, transport=transport)
    # Re-read local owner-managed gates before every reservation, allowing fast
    # rights withdrawal without waiting for a process restart or secret refresh.
    provider.before_request = config.validate
    return provider


class DurableSearchMetrics:
    def __init__(self, ledger):
        self.ledger = ledger

    def add(self, name):
        self.ledger.record_search_event(name)

    def snapshot(self):
        return self.ledger.search_metrics()


def create_search_application(config, **factory_options):
    from .gateway import SearchApplication
    provider = create_brave_provider(config, **factory_options)
    return SearchApplication(provider, metrics=DurableSearchMetrics(provider.ledger))
