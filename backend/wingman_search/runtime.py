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


def read_config(path, *, required_gates=None):
    try:
        path = Path(path)
        if path.stat().st_size > 16384:
            raise ValueError()
        from .contracts import decode_json
        value = decode_json(path.read_bytes(), 16384)
        config = SearchConfig(**value)
        config.validate(required_gates=required_gates)
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
    config.validate(required_gates={'live_search'})
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
    provider.before_request = lambda: config.validate(required_gates={'live_search'})
    return provider


class DurableSearchMetrics:
    def __init__(self, ledger):
        self.ledger = ledger

    def add(self, name):
        self.ledger.record_search_event(name)

    def snapshot(self):
        return self.ledger.search_metrics()


class RightsGatedAds:
    """Re-read independent rights gates on every public ad operation."""
    def __init__(self, service, config):
        self.service, self.config = service, config

    def _call(self, name, *args, **kwargs):
        self.config.validate(required_gates={'live_ads', 'production_billing'})
        return getattr(self.service, name)(*args, **kwargs)

    def issue_context(self, **kwargs):
        return self._call('issue_context', **kwargs)

    def decision(self, raw):
        return self._call('decision', raw)

    def event(self, raw):
        return self._call('event', raw)

    def asset(self, asset_id):
        return self._call('asset', asset_id)

    def close(self):
        return self.service.close()


def create_search_application(config, *, ads_factory=None, **factory_options):
    from .gateway import SearchApplication
    provider = create_brave_provider(config, **factory_options)
    ads = None
    ads_unavailable = False
    if config.live_ads:
        # This only OPENS an already initialized, independently authorized live
        # ledger. No test-store promotion, payment or auto-initialization exists.
        # The cloud search-only image deliberately omits this package; approved
        # advertising requires the documented single durable host deployment.
        try:
            config.validate(required_gates={'live_ads', 'production_billing'})
            if ads_factory is None:
                from wingman_ads.service import open_approved_live_service
                ads_factory = open_approved_live_service
            ads = RightsGatedAds(ads_factory(config.approved_ads_store_path), config)
        except Exception:
            # Ad rights/storage failure cannot disable an authorized organic
            # search. No paid ad event can pass this closed service boundary.
            ads_unavailable = True
    app = SearchApplication(provider, metrics=DurableSearchMetrics(provider.ledger), ads=ads)
    app.ads_unavailable = ads_unavailable
    return app
