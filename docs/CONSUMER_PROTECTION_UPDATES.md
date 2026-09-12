# Signed consumer protection updates

The consumer update pipeline is separate from curated content and optional Guard packs. `ConsumerProtectionRepository` restores authenticated cached releases, downloads a global release when configured, stages it transactionally, and requires native preparation/activation acknowledgements before changing the Dart browsing policy. There is no visited-URL, page-body, query or category-selection input to its transport.

## Configuration and current deployment

Production updates are **not configured** in this checkout. `assets/policy/consumer_update_keys.json` deliberately contains `{"schemaVersion":1,"keys":{}}`. There is no manufactured production signing key, private key, endpoint, or remote service. The immutable app-bundled baseline remains the initial protection source.

A release operator must place the approved Ed25519 public key bytes as base64 under a stable key ID in the bundled `keys` map, publish authenticated artifacts at a controlled HTTPS endpoint, and build with `--dart-define=WINGMAN_CONSUMER_UPDATE_URL=https://<controlled-host>/<directory>/manifest.json`. That example is a configuration shape, not an operational address. Private signing material stays outside the application and repository. Key rotation requires an application release retaining overlap for still-valid cached generations. A key in user preferences or downloaded metadata is never a trust anchor.

Ordinary startup runs legacy quarantine, restores/refreshes consumer protection, then loads policy/UI capabilities before creating page renderers. The refresh checks at startup with a persisted 24-hour throttle. The current integration does not perform live-session hot replacement on a timer. The web companion does not configure the source. Empty keys or absent endpoint yields `notConfigured` without an update request; browsing still requires its usable baseline/native capability.

## Signed artifact contract

The envelope has exactly three fields: `keyId`, `payload` (base64 of the exact UTF-8 manifest JSON bytes), and `signature` (base64 64-byte Ed25519 signature over those payload bytes). JSON is not reserialized before signature verification.

| Signed payload field | Required value or limit |
| --- | --- |
| `purpose` | `wingman-consumer-protection-v1`; prevents reuse of another signed content type |
| `schemaVersion` | `1` |
| `sequence` | Integer `2..2147483647`; independent of catalog/Guard sequences; bundled generation is `1` |
| `version` | 1–80 ASCII letters/digits plus `.`, `_`, `+`, `-`; first character alphanumeric |
| `generatedAt` | UTC ISO timestamp ending `Z`, no more than 24 hours into the future |
| `minimumAppVersion` | Three-part version no greater than the supported application version |
| `filename` | Exactly `consumer-<sequence>.json`, within the manifest's HTTPS directory |
| `sha256`, `bytes` | Lowercase 64-character SHA-256 and exact data length, at most 16 MiB |
| `license` | Nonempty provenance/license description, at most 4,096 characters |

The data uses the bundled consumer schema. Its sequence, version and generated timestamp must match the signed manifest. All six mandatory category sets must be nonempty; domain syntax, host/path rules and tracker entries must validate. A trusted signature does not bypass schema validation. Data and authenticated envelopes are immutable after validation.

Transport permits HTTPS only, uses normal certificate validation, rejects redirects, credentials, query strings and fragments on configuration, and bounds response size and duration. Signed filenames cannot change origin or escape the directory. No query or full page URL is logged by this pipeline.

## Native preparation and durable activation

All messages use the trusted Flutter channel `wingman/protected-browser`; pages have no JavaScript bridge to it.

| Method | Payload | Required result |
| --- | --- | --- |
| `prepareConsumerPolicy` | `envelope` and `data` byte arrays, `restore` boolean | `ready:true`, opaque `token`, matching `sequence` and `sha256` |
| `activateConsumerPolicy` | Prepared `token` | `activated:true` and matching generation/digest |
| `discardConsumerPolicy` | Prepared `token` | Discards unused preparation |
| `revertConsumerPolicy` | Prepared/activated `token` | `reverted:true` only when the previously usable policy is restored or activation never occurred |

Native code independently authenticates the signature using bundled public keys and validates data. iOS compiles all candidate WebKit rule groups before acknowledgement. Unsupported native verification or compilation leaves the release staged and preserves the active policy. Android update signature support is feature-gated; the bundled baseline remains available where the update verifier is unsupported.

SQLite stores authenticated release blobs, active/previous/pending pointers, highest accepted sequence and last-check time. Pending bytes are written in one transaction before native activation. A matching native receipt is followed by one transaction committing active/previous/highest state. A commit failure requests native revert. A lost native acknowledgement or failed revert exposes recovery rather than guessing success. Preparation is bounded to 45 seconds; activation/revert/discard calls are bounded to 10 seconds each. Late preparation does not authorize activation.

On restart, cached signatures and data are reverified before native restoration. A corrupt active release can recover the previous authenticated generation while retaining the replay high-water mark. Pending candidates are retried; they can represent a crash between native activation and durable pointer commit. Native receipts also retain accepted-generation history and prevent reopening a lower network release as a new update. Once an accepted cached native generation exists, failed native restoration closes browsing instead of silently falling back to an older policy. Missing native support never produces Dart-only activation.

## Evidence and remaining deployment work

Synthetic signed tests use freshly generated test keys only. They cover signature/purpose/key failures, modified/truncated data, missing categories, metadata/version mismatches, staged-only native support, replay rejection, SQLite corruption recovery, interrupted activation commits, offline retention, native failures, and callback timeouts. They do not establish operation of a production feed or physical-device update lifecycle. The existing policy/guard tests remain separate.

Before enabling a feed, validate its complete licensed category coverage, operate the signing/publishing process, and demonstrate install → update → restart → failed compilation → previous-generation recovery on both devices. This implementation does not remove the limited alcohol/drug/tobacco data coverage or Android resource-redirect limitations in [PROTECTION_COVERAGE.md](PROTECTION_COVERAGE.md).
