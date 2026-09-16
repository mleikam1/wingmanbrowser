"""Reviewed source configuration, also used to generate the app trust registry."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

SCOPES = {"technology-reporting", "science-reporting", "public-information",
          "sports-reporting", "general-reporting", "lifestyle-education", "sponsored-features", "health-reporting"}
REGISTRY_KEYS = ("id", "name", "homepageUrl", "language", "topics", "allowedArticleHosts",
                 "articlePathPrefixes", "eligibilityScope", "rights", "enabled", "verifiedAt",
                 "feedUrl", "feedRedirectHosts", "minRefreshSeconds", "retentionSeconds",
                 "articleUrlFormat", "requiredTopicTerms", "requiresAttribution",
                 "imagePolicy", "preserveFeedText", "displayMode", "branding", "publisherId", "feedCompatibility")


def load_config(path):
    raw = json.loads(Path(path).read_text())
    if raw.get("schemaVersion") != 1 or not 1 <= len(raw.get("sources", [])) <= 256:
        raise ValueError("Invalid source configuration")
    seen = set()
    for source in raw["sources"]:
        sid = source["id"]
        if not re.fullmatch(r"[a-z0-9-]{1,80}", sid) or sid in seen:
            raise ValueError("Invalid or duplicate source id")
        seen.add(sid)
        if source["eligibilityScope"] not in SCOPES or source["language"] != "en":
            raise ValueError("Unreviewed source scope/language")
        for field in ("feedRedirectHosts", "allowedArticleHosts"):
            if not source.get(field) or any(not re.fullmatch(r"[a-z0-9.-]+", host)
                                            for host in source[field]):
                raise ValueError("Invalid source hosts")
        feed = urlsplit(source["feedUrl"])
        if (feed.scheme != "https" or feed.hostname not in source["feedRedirectHosts"]
                or feed.username or feed.password or feed.port not in (None, 443)):
            raise ValueError("Invalid configured feed")
        rights = source["rights"]
        if rights["titles"] is not True or not isinstance(rights.get("images"), bool):
            raise ValueError("Title and image reuse require explicit reviewed decisions")
        if not isinstance(rights.get("excerpts"), bool):
            raise ValueError("Excerpt reuse must be an explicit reviewed boolean")
        if not rights.get("attribution") or not rights.get("licenseUrl", "").startswith("https://"):
            raise ValueError("Missing rights provenance")
        if not 1800 <= source["minRefreshSeconds"] <= 31622400:
            raise ValueError("Invalid refresh interval")
        if not 3600 <= source["retentionSeconds"] <= 604800:
            raise ValueError("Invalid cache retention")
        if not isinstance(source["enabled"], bool) or not source.get("articlePathPrefixes"):
            raise ValueError("Missing explicit article scope")
        if source.get("articleUrlFormat", "path-prefix") not in ("path-prefix", "dated-story"):
            raise ValueError("Invalid article URL format")
        terms = source.get("requiredTopicTerms", [])
        if not isinstance(terms, list) or len(terms) > 30 or any(
                not isinstance(term, str) or not term.strip() or len(term) > 80 for term in terms):
            raise ValueError("Invalid topic scope terms")
        if not isinstance(source.get("requiresAttribution", False), bool):
            raise ValueError("Invalid author attribution requirement")
        if any(not isinstance(prefix, str) or not prefix.startswith("/") or
               any(part in (".", "..") for part in prefix.split("/")) or "\\" in prefix
               for prefix in source["articlePathPrefixes"]):
            raise ValueError("Invalid article path prefix")
        if any(not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{32}", value)
               for value in source.get("revokedItemIds", [])):
            raise ValueError("Invalid revoked item identifier")
        mode = source.get("displayMode", "publisher-link")
        if mode not in ("publisher-link", "sponsored-syndication"):
            raise ValueError("Invalid display mode")
        if mode == "sponsored-syndication" and (source["eligibilityScope"] != "sponsored-features"
                or not source.get("preserveFeedText") or rights["excerpts"]):
            raise ValueError("Syndication requires its separate full-article contract")
        if source.get("imagePolicy"):
            from .media import validate_image_policy
            validate_image_policy(source)
        if source.get('feedCompatibility') is not None and not (
                source['feedCompatibility'] == 'nasa-photojournal-self-link-v1' and
                source['id'] == 'nasa-photojournal' and
                source['feedUrl'] == 'https://science.nasa.gov/feed/photojournal/latest-content/'):
            raise ValueError('Unreviewed feed compatibility adapter')
        if rights["images"] and not source.get("imagePolicy"):
            raise ValueError("Image rights require a reviewed image policy")
        brand = source.get("branding")
        if brand is not None:
            from .normalize import date_value
            if (brand.get("approved") is not True or
                    not re.fullmatch(r"assets/publisher_logos/[A-Za-z0-9_/-]+\.(png|webp|jpg|jpeg)", brand.get("asset", "")) or
                    ".." in brand["asset"] or not date_value(brand.get("reviewedAt")) or
                    not brand.get("usageBasis") or
                    not all(brand.get(k, "").startswith("https://") for k in ("sourceUrl", "termsUrl"))):
                raise ValueError("Invalid reviewed bundled branding")
    return raw


def registry(config):
    return {"schemaVersion": 1, "requireStoryImages": config.get("requireStoryImages", False),
            **({'reviewStatusByTopic': config['reviewStatusByTopic']} if config.get('reviewStatusByTopic') else {}), "sources": [
        {key: source[key] for key in REGISTRY_KEYS if key in source}
        for source in config["sources"]]}
