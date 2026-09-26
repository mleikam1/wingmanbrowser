"""Independent operational gates. These never relax mandatory protection."""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
from urllib.parse import urlsplit


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class SearchConfig:
    profile: str = "fixtures"
    environment: str = "local"
    live_search: bool = False
    cached_news: bool = False
    remote_media: bool = False
    live_ads: bool = False
    partner_demand: bool = False
    production_billing: bool = False
    live_development_cap_micros: int = 0
    production_gateway_url: str | None = None
    shared_ledger_kind: str | None = None
    shared_project: str | None = None
    shared_bucket: str | None = None
    shared_object: str = "wingman-operations/brave-budget.json"
    deployment_approval_reference: str | None = None
    provider_spend_approval_reference: str | None = None
    secret_manager_reference: str | None = None
    production_cap_micros: int = 0
    production_unit_cost_micros: int = 5000
    rights_register_path: str | None = None
    approved_ads_store_path: str | None = None
    ads_runtime: str | None = None

    def validate(self, *, required_gates=None) -> None:
        scope = GATES if required_gates is None else frozenset(required_gates)
        if not scope <= GATES:
            raise ConfigurationError("unknown_rights_gate")
        if self.profile not in {"fixtures", "smoke", "approved-local", "production"}:
            raise ConfigurationError("unsupported_profile")
        if self.environment not in {"local", "production"}:
            raise ConfigurationError("unsupported_environment")
        if type(self.live_development_cap_micros) is not int or self.live_development_cap_micros < 0:
            raise ConfigurationError("invalid_budget_configuration")
        if any(type(getattr(self, flag)) is not bool for flag in GATES):
            raise ConfigurationError("invalid_operational_gate")
        if self.live_ads and scope & {'live_ads', 'production_billing'}:
            if (self.environment != "production" or not self.production_billing
                    or self.ads_runtime != "single-durable-host"
                    or not isinstance(self.approved_ads_store_path, str)
                    or not Path(self.approved_ads_store_path).is_absolute()):
                raise ConfigurationError("approved_durable_ads_configuration_required")
        elif not self.live_ads and scope & {'live_ads', 'production_billing'} and (self.approved_ads_store_path is not None or self.ads_runtime is not None):
            raise ConfigurationError("ads_configuration_requires_live_ads_gate")
        if self.profile == "fixtures" and any(getattr(self, flag) for flag in GATES):
            raise ConfigurationError("fixture_profile_cannot_dispatch")
        if self.profile == "smoke" and self.environment != "local":
            raise ConfigurationError("smoke_is_local_only")
        if self.environment == "production":
            if self.profile != "production":
                raise ConfigurationError("production_profile_required")
            validate_production_url(self.production_gateway_url)
            if (not self.live_search or self.shared_ledger_kind != "gcs"
                    or type(self.production_cap_micros) is not int or self.production_cap_micros <= 0
                    or type(self.production_unit_cost_micros) is not int or self.production_unit_cost_micros <= 0
                    or not isinstance(self.deployment_approval_reference, str)
                    or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,79}", self.deployment_approval_reference)
                    or not self.rights_register_path):
                raise ConfigurationError("production_authorization_configuration_required")
            from .shared_budget import validate_location
            from .budget import BudgetError
            try:
                validate_location(self.shared_project, self.shared_bucket, self.shared_object,
                                  self.provider_spend_approval_reference)
            except BudgetError:
                raise ConfigurationError("production_shared_ledger_configuration_required") from None
            secret_pattern = (r"projects/" + re.escape(self.shared_project) +
                              r"/secrets/[A-Za-z0-9_-]{1,255}/versions/(?:[1-9][0-9]*|latest)")
            if not isinstance(self.secret_manager_reference, str) or not re.fullmatch(secret_pattern, self.secret_manager_reference):
                raise ConfigurationError("approved_secret_manager_reference_required")
            rights = load_rights(Path(self.rights_register_path))
            host = urlsplit(self.production_gateway_url).hostname
            if not isinstance(rights.get("approved_domains"), list) or host not in rights["approved_domains"]:
                raise ConfigurationError("production_domain_not_approved")
            # Organic API spending and advertiser billing are separate approvals.
            for gate in scope:
                if getattr(self, gate):
                    require_right(rights, gate)
        elif self.profile == "production":
            raise ConfigurationError("production_environment_required")


def validate_production_url(value: str | None) -> None:
    import ipaddress
    try:
        url = urlsplit(value or "")
        host = url.hostname or ""
        if (url.scheme != "https" or not host or url.username or url.password
                or url.query or url.fragment or url.port not in {None, 443}
                or host == "localhost" or host.endswith((".localhost", ".local", ".test", ".invalid"))
                or "." not in host):
            raise ValueError()
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            address = None
        if address is not None and not address.is_global:
            raise ValueError()
    except ValueError:
        raise ConfigurationError("invalid_production_gateway") from None


GATES = frozenset({"live_search", "cached_news", "remote_media", "live_ads",
                   "partner_demand", "production_billing"})


def load_rights(path: Path) -> dict:
    try:
        if path.stat().st_size > 64 * 1024:
            raise ValueError()
        register = json.loads(path.read_text(encoding="utf-8"))
        if register.get("schema_version") != 1 or set(register.get("gates", {})) != GATES:
            raise ValueError()
        domains = register.get("approved_domains", [])
        if (not isinstance(domains, list) or len(domains) > 50 or len(domains) != len(set(domains))
                or any(not isinstance(host, str) or not re.fullmatch(
                    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", host)
                    for host in domains)):
            raise ValueError()
        for host in domains:
            validate_production_url("https://" + host)
        for gate in register["gates"].values():
            if gate.get("enabled") is not False and gate.get("enabled") is not True:
                raise ValueError()
            if gate["enabled"] and (gate.get("authorization_status") != "approved"
                                    or not gate.get("evidence_reference")):
                raise ValueError()
        return register
    except (OSError, ValueError, TypeError, AttributeError):
        raise ConfigurationError("invalid_rights_register") from None


def require_right(rights: dict, gate: str) -> None:
    if gate not in GATES:
        raise ConfigurationError("unknown_rights_gate")
    entry = rights.get("gates", {}).get(gate, {})
    if (entry.get("enabled") is not True or entry.get("authorization_status") != "approved"
            or not entry.get("evidence_reference")):
        raise ConfigurationError("rights_gate_closed")
