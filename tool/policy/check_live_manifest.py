#!/usr/bin/env python3
"""Check that Dart, Android and iOS pin the exact reviewed manifest bytes.

Read-only: it never enables a site, changes pins or extends an expiry date.
Content review and native compatibility tests are separate requirements.
"""

import hashlib
import json
from pathlib import Path
import re


def main():
    root = Path(__file__).resolve().parents[2]
    data = (root / "assets/policy/live_sites.json").read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    pins = {
        "lib/policy/live_manifest_hash.dart": r"liveManifestSha256\s*=\s*'([a-f0-9]{64})'",
        "android/app/src/main/kotlin/com/wingmanbrowser/wingman_browser/ProtectedWebBridge.kt": r'CATALOG_SHA256\s*=\s*"([a-f0-9]{64})"',
        "ios/Runner/ProtectedWebBridge.swift": r'catalogSHA256\s*=\s*"([a-f0-9]{64})"',
    }
    for path, pattern in pins.items():
        match = re.findall(pattern, (root / path).read_text())
        if match != [digest]:
            raise ValueError(f"Manifest pin mismatch: {path}")
    manifest = json.loads(data)
    enabled = [site for site in manifest["sites"] if site["enabled"]]
    print(f"All three application pins match: {digest}")
    print(
        f"{len(data)} manifest bytes; {len(enabled)} enabled sources; "
        f"{sum(len(s['documents']) for s in enabled)} exact documents; "
        f"{sum(len(s['resources']) for s in enabled)} exact passive resources; "
        f"{len(manifest['privacy']['domains'])} privacy domain rules."
    )
    print(f"Review expires {manifest['expiresAt']}; no files changed.")


if __name__ == "__main__":
    main()
