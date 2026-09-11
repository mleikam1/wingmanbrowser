#!/usr/bin/env python3
"""Reproduce the reviewed EasyPrivacy adaptation; never activate an update.

Writes a review artifact at --output, not the authoritative live manifest.
No browsing URL, profile, account or secret is read or sent.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request


COMMIT = "7f83d42234e8a2737a924bbd4d3d0301da0f224e"
SOURCE_SHA256 = "263c91173748a3adb099aeb139081a240addb1885efa6e31ef7b9538b5faa74d"
SOURCE_URL = (
    "https://raw.githubusercontent.com/easylist/easylist/"
    + COMMIT
    + "/easyprivacy/easyprivacy_trackingservers_thirdparty.txt"
)
MAX_BYTES = 1024 * 1024
RULE = re.compile(r"\|\|([a-z0-9.-]+)\^\$third-party")
LABEL = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?")


def build(source: bytes) -> dict:
    if len(source) > MAX_BYTES or hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        raise ValueError("The pinned source changed or exceeds its byte limit")
    domains = set()
    for line in source.decode("utf-8", errors="strict").splitlines():
        match = RULE.fullmatch(line)
        if not match:
            continue
        host = match.group(1)
        if len(host) > 253 or not all(LABEL.fullmatch(label) for label in host.split(".")):
            raise ValueError("Invalid domain in supported upstream rule")
        domains.add(host)
    if len(domains) != 2501:
        raise ValueError("Unexpected reviewed rule count")
    return {
        "version": "2026.09.11.1",
        "sourceUrl": SOURCE_URL,
        "sourceCommit": COMMIT,
        "sourceSha256": SOURCE_SHA256,
        "license": "CC-BY-SA-3.0",
        "scope": "third-party-subresources",
        "domains": sorted(domains),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-file", type=Path, help="Use an already downloaded source")
    parser.add_argument("--output", type=Path, required=True, help="New review artifact path")
    args = parser.parse_args()
    if args.source_file:
        data = args.source_file.read_bytes()
    else:
        request = urllib.request.Request(
            SOURCE_URL, headers={"User-Agent": "Wingman-policy-maintainer/1"}
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.url != SOURCE_URL or response.status != 200:
                raise ValueError("Unexpected policy-source response")
            data = response.read(MAX_BYTES + 1)
    result = build(data)
    with args.output.open("x", encoding="utf-8") as target:
        json.dump(result, target, indent=2)
        target.write("\n")
    print(f"Reproduced {len(result['domains'])} rules for review at {args.output}")
    print("No live manifest, app pin, policy date or remote service was changed.")


if __name__ == "__main__":
    main()
