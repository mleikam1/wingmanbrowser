"""Independent operational gates. These never relax mandatory protection."""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
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

    def validate(self) -> None:
        if self.profile not in {"fixtures", "smoke", "approved-local", "production"}:
            raise ConfigurationError("unsupported_profile")
        if self.environment not in {"local", "production"}:
            raise ConfigurationError("unsupported_environment")
        if type(self.live_development_cap_micros) is not int or self.live_development_cap_micros < 0:
            raise ConfigurationError("invalid_budget_configuration")
        if self.profile == "fixtures" and (self.live_search or self.production_billing):
            raise ConfigurationError("fixture_profile_cannot_dispatch")
        if self.profile == "smoke" and self.environment != "local":
            raise ConfigurationError("smoke_is_local_only")
        if self.environment == "production":
            if self.profile != "production":
                raise ConfigurationError("production_profile_required")
            validate_production_url(self.production_gateway_url)
            # No selected deployment target/shared durable ledger exists yet.
            raise ConfigurationError("production_not_authorized_or_implemented")


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
