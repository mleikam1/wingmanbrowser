"""Rights-gated shared editorial Brave news; never accepts consumer queries."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

from wingman_search.budget import BudgetError
from wingman_search.config import ConfigurationError, load_rights, require_right
from wingman_search.contracts import SearchError, SearchRequest
from .normalize import canonical_url, currents_topics, date_value, iso, item_id, plain
from .provider import NewsProvider, is_unexpired

# Existing canonical categories/preferences; public editorial topics are identical
# for every reader. No user interest, identifier or submitted query enters here.
EDITORIAL_QUERIES = {
    "general": "public interest news reporting",
    "sport": "sports results reporting",
    "arts_culture_entertainment": "arts culture museums reporting",
    "science_technology": "science technology research news",
    "economy_business_finance": "economy business reporting",
    "education": "education learning research news",
    "environment": "environment conservation research news",
    "health": "public health medical research news",
}
INTERVAL_MICROS = 2 * 60 * 60 * 1_000_000
TICK_SECONDS = 15 * 60
BRAVE_SOURCE_ID = "brave-news"


def default_rights_loader():
    return load_rights(Path(__file__).absolute().parents[1] / "config" / "brave_rights.json")


def shared_grant(rights, source=None):
    """Return documented preview lifetime; a short TTL alone is never a grant."""
    try:
        require_right(rights, "cached_news")
        seconds = rights.get("storage_duration_seconds")
        reference = rights["gates"]["cached_news"]["evidence_reference"]
        if (type(seconds) is not int or not 3600 <= seconds <= 86400
                or rights.get("shared_news_use") != "approved"
                or rights.get("cdn_fanout") != "approved"):
            raise ValueError()
        if source is not None:
            grant = source.get("sharedNewsGrant", {})
            if (source.get("providerId") != "brave" or source.get("id") != BRAVE_SOURCE_ID
                    or not source.get("enabled") or not source.get("rights", {}).get("titles")
                    or source.get("rights", {}).get("images") is not False
                    or grant.get("status") != "approved" or grant.get("reference") != reference
                    or type(grant.get("retentionSeconds")) is not int
                    or not 3600 <= grant["retentionSeconds"] <= seconds):
                raise ValueError()
            seconds = min(seconds, grant["retentionSeconds"], source["retentionSeconds"])
        return reference, seconds
    except (ConfigurationError, ValueError, TypeError, KeyError, AttributeError):
        raise ConfigurationError("brave_shared_news_rights_required") from None


def shared_news_allowed(rights_loader=default_rights_loader):
    try:
        shared_grant(rights_loader())
        return True
    except Exception:
        return False


def source_definition():
    """Disabled manifest; installation of a source is not authorization to cache."""
    return {
        "id": BRAVE_SOURCE_ID, "name": "Wingman News · Brave", "providerId": "brave",
        "homepageUrl": "https://brave.com/search/api/", "language": "en", "region": "us",
        "topics": ["headlines", "sports", "entertainment", "science_technology", "science", "technology",
                   "business", "education", "environment", "health"],
        "allowedArticleHosts": [], "articleHostPolicy": "validated-public", "articlePathPrefixes": ["/"],
        "eligibilityScope": "brave-preview", "feedUrl": "https://api.search.brave.com/res/v1/news/search",
        "feedRedirectHosts": ["api.search.brave.com"], "minRefreshSeconds": TICK_SECONDS,
        "retentionSeconds": 86400, "enabled": False, "verifiedAt": "2026-09-26T00:00:00Z",
        "rights": {"titles": False, "excerpts": False, "images": False,
                   "attribution": "Original publisher; results supplied by Brave Search API",
                   "licenseUrl": "https://api-dashboard.search.brave.com/terms-of-service"},
        "providerAttribution": {"label": "Results supplied by Brave Search API", "url": "https://brave.com/search/api/"},
        "sharedNewsGrant": {"status": "unknown", "reference": None, "retentionSeconds": None},
    }


class _ScheduledLedger:
    def __init__(self, ledger, slot):
        self.ledger, self.slot = ledger, slot
    def reserve(self, endpoint):
        if endpoint != "news":
            raise BudgetError("scheduled_news_endpoint_required")
        return self.ledger.reserve_scheduled(self.slot, INTERVAL_MICROS)
    def complete(self, reservation, **fields):
        return self.ledger.complete(reservation, **fields)


class BraveNewsProvider(NewsProvider):
    def __init__(self, provider=None, *, provider_factory=None, rights_loader=default_rights_loader):
        self.provider, self.provider_factory = provider, provider_factory
        self.rights_loader = rights_loader
        self.writer_guard = None

    def bind_writer_guard(self, guard):
        self.writer_guard = guard

    def retain_authorized(self, source, prior, now):
        state = dict(prior)
        try:
            reference, seconds = shared_grant(self.rights_loader(), source)
        except Exception:
            return dict(state, items=[], bravePools={}, rightsBlocked=True,
                        status="not-configured", error="brave-shared-rights-required",
                        nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)))
        pools = {}
        previous_pools = prior.get("bravePools", {})
        if not isinstance(previous_pools, dict):
            previous_pools = {}
        for key, rows in previous_pools.items():
            if key not in EDITORIAL_QUERIES:
                continue
            kept = []
            for item in rows if isinstance(rows, list) else []:
                if not isinstance(item, dict) or not isinstance(item.get('rights'), dict):
                    continue
                fetched = date_value(item.get("fetchedAt"))
                expiry = date_value(item.get("expiresAt"))
                if (item.get("sharedGrantReference") == reference and fetched and expiry
                        and fetched <= now and expiry <= fetched + timedelta(seconds=seconds)
                        and is_unexpired(item, now)):
                    kept_item = dict(item, image=None, rights=dict(item['rights'], excerpt=source['rights']['excerpts'], image=False))
                    if not source['rights']['excerpts']:
                        kept_item.pop('excerpt', None)
                        kept_item.pop('excerptProvenance', None)
                    kept.append(kept_item)
            pools[key] = kept
        return dict(state, bravePools=pools, items=self._merge(pools), rightsBlocked=False)

    @staticmethod
    def _merge(pools):
        by_url = {}
        for rows in pools.values():
            for item in rows:
                old = by_url.get(item["canonicalUrl"])
                if old is None:
                    by_url[item["canonicalUrl"]] = dict(item)
                else:
                    # Membership only, never cross-source copyright or assets.
                    old["topics"] = sorted(set(old["topics"]) | set(item["topics"]))
                    old["providerCategories"] = sorted(set(old["providerCategories"]) | set(item["providerCategories"]))
        return list(by_url.values())[:160]

    def refresh(self, source, prior, now):
        if source.get("providerId") != "brave" or source.get("id") != BRAVE_SOURCE_ID:
            raise ValueError("brave-source-mismatch")
        state = self.retain_authorized(source, prior, now)
        if state.get("rightsBlocked"):
            return state
        if self.provider is None and self.provider_factory is not None:
            try:
                self.provider = self.provider_factory()
            except Exception:
                return dict(state, error="brave-unconfigured", status="not-configured", lastHttpStatus=None,
                            nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)))
        if self.provider is None:
            return dict(state, error="brave-unconfigured", status="not-configured", lastHttpStatus=None,
                        nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)))
        if self.writer_guard is None:
            raise BudgetError("shared_news_writer_guard_required")
        reference, seconds = shared_grant(self.rights_loader(), source)
        ledger = self.provider.ledger
        current_micros = int(now.timestamp() * 1_000_000)
        # One current phase per tick; skipped phases never cause a catch-up burst.
        phase = int(now.timestamp() // TICK_SECONDS) % len(EDITORIAL_QUERIES)
        category = tuple(EDITORIAL_QUERIES)[phase]
        slot = "brave-" + category
        due = ledger.schedule_due(slot)
        if due is not None and current_micros < due:
            return dict(state, nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)), error=None)
        self.writer_guard()
        # A fresh adapter keeps this fixed slot out of ordinary user search state.
        from wingman_search.provider import BraveProvider
        scheduled = BraveProvider(_ScheduledLedger(ledger, slot), self.provider._key,
                                  transport=self.provider.transport, policy=self.provider.policy)
        def before_request():
            self.writer_guard()
            shared_grant(self.rights_loader(), source)
            if self.provider.before_request is not None:
                self.provider.before_request()
        scheduled.before_request = before_request
        try:
            dto, _ = scheduled.search(SearchRequest(EDITORIAL_QUERIES[category], "news"), count=20)
        except (BudgetError, SearchError) as error:
            return dict(state, error=error.code, status="cached" if state.get("items") else "unavailable",
                        lastHttpStatus=getattr(error, "provider_status", None),
                        nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)),
                        jobReport=[{"category": category, "status": error.code}])
        except ConfigurationError:
            return dict(self.retain_authorized(source, state, now), error="brave-configuration-required",
                        status="not-configured", nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)))
        self.writer_guard()
        # Recheck a concurrently revoked grant before storing even a successful reply.
        try:
            reference, seconds = shared_grant(self.rights_loader(), source)
        except ConfigurationError:
            return self.retain_authorized(source, {}, now)
        previous_by_url = {item["canonicalUrl"]: item for item in state.get("items", [])}
        rows = []
        for result in dto["results"]:
            url = canonical_url(result["url"], source)
            if not url:
                continue
            old = previous_by_url.get(url)
            # Repeated discovery does not extend a stored representation's grant.
            fetched = date_value(old.get("fetchedAt")) if old else now
            expiry = date_value(old.get("expiresAt")) if old else now + timedelta(seconds=seconds)
            if old and (not fetched or not expiry or expiry <= now):
                continue
            page_date = date_value(result.get("pageDate"))
            provider_fetched = date_value(result.get("providerFetchedAt"))
            if page_date and page_date < now - timedelta(days=30):
                continue
            title, excerpt = plain(result["title"], 500, preserve=True), plain(result.get("description", ""), 800, preserve=True)
            host = urlsplit(url).hostname.removeprefix("www.")
            item = {"id": item_id(url), "sourceId": BRAVE_SOURCE_ID, "providerId": "brave",
                    "publisherId": host, "publisherName": host, "providerCategories": [category],
                    "title": title, "canonicalUrl": url, "originalUrl": result["url"], "outboundUrl": result["url"],
                    "publishedAt": None, "discoveredAt": old.get("discoveredAt") if old else iso(now),
                    "pageDate": iso(page_date) if page_date and page_date <= now else None,
                    "providerFetchedAt": iso(provider_fetched) if provider_fetched and provider_fetched <= now else None,
                    "fetchedAt": iso(fetched), "expiresAt": iso(expiry), "language": "en",
                    "topics": currents_topics([category], title, excerpt), "image": None,
                    "sharedGrantReference": reference, "sharedGrantRetentionSeconds": seconds,
                    "rights": {"title": True, "excerpt": source["rights"]["excerpts"], "image": False,
                               "licenseUrl": source["rights"]["licenseUrl"]},
                    "eligibility": {"state": "eligible", "basis": "provider-preview", "scope": "brave-preview",
                                    "reviewedAt": source["verifiedAt"]},
                    "providerAttribution": source["providerAttribution"]}
            if source["rights"]["excerpts"] and excerpt:
                item.update(excerpt=excerpt, excerptProvenance={"field": "api-description", "format": "plain-text", "shortened": len(result.get("description", "")) > 800})
            rows.append(item)
        pools = dict(state.get("bravePools", {}))
        pools[category] = rows
        return dict(state, bravePools=pools, items=self._merge(pools), fetchedAt=iso(now), lastSuccessAt=iso(now),
                    nextRefreshAt=iso(now + timedelta(seconds=TICK_SECONDS)), status="fresh" if rows else "valid-empty",
                    lastHttpStatus=200, error=None, failures=0,
                    jobReport=[{"category": category, "status": "fresh" if rows else "valid-empty", "items": len(rows)}])
