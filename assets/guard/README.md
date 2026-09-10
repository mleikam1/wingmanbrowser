# Wingman starter filter pack

This is a small, manually authored development pack, not comprehensive category
or threat intelligence. Domain rules describe a site's primary purpose; no URL
keyword or page-text classifier is used. Mixed-purpose destinations can contain
support or educational material, so category exceptions and reporting remain
necessary. Support rules only exempt categories, never threat/custom blocks.

The factual domain selections were independently authored for Wingman and are
dedicated under **CC0-1.0**. They are not copied from a third-party blocklist.
Primary destination URLs appear as `source` metadata in the artifact. These
references document the limited selection, not a partnership or endorsement.
The reserved `*.guard.test` records are safe synthetic classifier fixtures and
do not promise a resolvable website. Malware/phishing/download threat records in
this starter are synthetic only. Native engine security remains separate.

`manifest.json` signs exact base64-carried JSON payload bytes using Ed25519. The
payload pins the global NDJSON artifact's SHA-256 digest, size, record count,
release sequence, version, creation time, minimum application version and license.
A second signed `rulesSha256` binds the native-readable SQLite index: sort by
`(host, kind, category)`; encode each row as the UTF-8 JSON array
`[host, kind, category, include_subdomains, rule_id]` followed by a newline; hash
the stream. Startup and rollback verify both archive and index before exposing
the database to native readers. Failure retains the current/previous evidence.
`public_keys.json` contains a development public verification key only. The
development signing seed is kept outside this repository; it is never an app
asset. Tests create independent keys which are not trusted by the app.

Production releases require a separately provisioned, protected signing key,
reviewed coverage/list licensing and a real configured HTTPS control-plane source.
There is no active update endpoint or hidden fallback network classifier.

CC0 text: <https://creativecommons.org/publicdomain/zero/1.0/legalcode>

The importer caps a manifest at 64 KiB, one global artifact at 64 MiB, and a
release at 500,000 rules. It retains the active and previous successful releases.
The SQLite index uses `(generation, host, kind, category)` keys; navigation uses
suffix equality queries rather than scanning the artifact. The optional normal
session cache holds at most 512 hosts for 10 minutes; private lookups bypass it.
Updates stream with size limits, reject redirects, and check no more than once
per 24 hours unless the user explicitly requests a check. No update URL is
configured in this build, so bundled classification works without a network.

The development authoring tool accepts `--development-key-output` for a new key
outside the repository, or `--development-key-input` to reuse an existing external
key. Do not use this development key for a public production release.
