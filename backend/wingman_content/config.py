"""Reviewed source configuration, also used to generate the app trust registry."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

SCOPES = {"technology-reporting", "science-reporting", "public-information",
          "sports-reporting", "general-reporting", "lifestyle-education"}
REGISTRY_KEYS = ("id", "name", "homepageUrl", "language", "topics", "allowedArticleHosts",
                 "articlePathPrefixes", "eligibilityScope", "rights", "enabled", "verifiedAt")


def load_config(path):
    raw = json.loads(Path(path).read_text())
    if raw.get("schemaVersion") != 1 or not 1 <= len(raw.get("sources", [])) <= 20:
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
        if rights["titles"] is not True or rights["images"] is not False:
            raise ValueError("Initial adapter requires reviewed title rights and no images")
        if not isinstance(rights.get("excerpts"), bool):
            raise ValueError("Excerpt reuse must be an explicit reviewed boolean")
        if not rights.get("attribution") or not rights.get("licenseUrl", "").startswith("https://"):
            raise ValueError("Missing rights provenance")
        if not 900 <= source["minRefreshSeconds"] <= 86400:
            raise ValueError("Invalid refresh interval")
        if not 3600 <= source["retentionSeconds"] <= 604800:
            raise ValueError("Invalid cache retention")
        if not isinstance(source["enabled"], bool) or not source.get("articlePathPrefixes"):
            raise ValueError("Missing explicit article scope")
        if any(not isinstance(prefix, str) or not prefix.startswith("/") or
               any(part in (".", "..") for part in prefix.split("/")) or "\\" in prefix
               for prefix in source["articlePathPrefixes"]):
            raise ValueError("Invalid article path prefix")
        if any(not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{32}", value)
               for value in source.get("revokedItemIds", [])):
            raise ValueError("Invalid revoked item identifier")
    return raw


def registry(config):
    return {"schemaVersion": 1, "sources": [
        {key: source[key] for key in REGISTRY_KEYS if key in source}
        for source in config["sources"]]}
