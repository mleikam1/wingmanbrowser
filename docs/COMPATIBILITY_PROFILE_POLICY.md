# Compatibility reporting and corrections

Wingman repairs a supported experience without changing whether content is eligible. This milestone remains a bundled, reviewed plain-text reader. It does not restore live websites, sign-in, media, uploads, downloads or external browser dispatch.

## Current status

**Implemented and tested:** the minimal report schema, strict optional-domain validation, an empty production correction registry, bounded correction-pack validation, exact resource/digest matching, and a controlled reader-layout repair with policy-denied siblings remaining closed. The final focused run passed 72 tests: 26 privacy/compatibility/export tests, 8 startup-hydration tests and 38 workspace/storage/session/measurement tests; scoped analysis was clean. The run log is `work/signature-owned-tests-handoff.log` in the parent workspace. Full application/platform results are recorded separately in [Feature acceptance](FEATURE_ACCEPTANCE_TESTS.md) and [Signature status](SIGNATURE_FEATURES_STATUS.md).

**Partial:** the reporting pipeline ends at an explicit, previewed clipboard export. No submission endpoint, inbox, support-account integration or server response exists. The UI says “Nothing was submitted.” No production compatibility profile is bundled: a synthetic fixture is evidence that the mechanism works, not evidence of a real website defect or a reviewed production fix.

**Disabled pending review:** remote correction distribution and diagnostic submission. They have no network implementation or configured provider. A future remote pack must have an authenticated signature and a durable anti-replay/revocation checkpoint in addition to the validation below. Signing proves who published a pack, not that its behavior is safe.

## Optional report

`CompatibilityReport` contains only schema version, local-only status, one issue enum, app version, coarse capability, mandatory policy version and a UTC-hour timestamp. Issues are page load, sign-in, upload/download, media, layout/interaction or other. The capability disclosure explicitly states that current content is a bundled reader.

The domain is absent by default. A user must opt in, review a bare domain, preview the report and then press **Copy reviewed report**. Supplying a suggested domain never opts the user in. An edit invalidates the preview. URLs, paths, ports, credentials, fragments and query strings are rejected rather than stripped; Unicode domains must be provided in their visible ASCII form. A domain can itself reveal sensitive interests. No full address, history, query, note, page text, screenshot, cookie, token, device identifier or network trace is collected by this report.

The report stays in the screen's memory and is discarded when the screen closes. Only typed `compatibilityReportPrepared` and `compatibilityReportExported` journal events are recorded, with no domain or issue text. Private-session events use that session's memory-only journal. The owner is responsible for passing a live session/route gate; the screen also checks foreground/current-route state before copying and suppresses stale completion messages.

Copying uses Flutter's system clipboard API after preview. Other apps and system clipboard services may access the exported text; it is not a private Wingman storage boundary. Copy success is recorded only when the API completes, and a failure is labeled unconfirmed. No successful-copy message claims delivery to Wingman. [Flutter Clipboard.setData](https://api.flutter.dev/flutter/services/Clipboard/setData.html), [Android clipboard behavior](https://developer.android.com/develop/ui/views/touch-and-input/copy-paste)

Clipboard behavior can include OS features such as Apple's cross-device clipboard; Flutter's basic API exposes no per-copy local-only option. This implementation therefore discloses clipboard exposure instead of claiming device-only isolation for exported text. The private/handoff journal persistence boundary remains separate from an owner's explicit export. Guest handoff has no report or export controls. [Apple pasteboard local-only option](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly)

## Fixed correction schema

A version-1 pack has exactly `schema`, `sequence`, `profiles` and `revokedIds`. Input is limited to 64 KiB, 32 profiles and 256 revocations. Each record has exactly:

| Field | Meaning |
|---|---|
| `id`, `resourceId` | Bounded identifiers, one correction per exact resource |
| `resourceSha256` | Exact signed body digest; a different revision receives no correction |
| `policyVersion` | Must match the resource's authoritative policy version |
| `correction` | The sole supported value is `wrapLongLines` |
| `evidence`, `evidenceId` | Controlled-fixture or reviewed-production provenance plus an audit-record reference |
| `reviewedAt`, `expiresAt` | Current review, with a maximum 90-day validity interval |

Unknown fields and correction values fail validation. There is no URL, domain wildcard, dependency allowlist, JavaScript, HTML, native configuration, TLS exception, permission grant, cookie access or tracking exemption in the schema. A record cannot supply replacement page text. Review metadata is not independent evidence of a completed review; production installation requires the actual reviewed source artifact and evidence record. No user/import/remote path installs packs in this version.

`CompatibilityProfileRegistry.resolve` first calls the existing authoritative content policy. Only an eligible signed resource is looked up for a correction. Exact ID, digest, policy version, review time and revocation must all match. Additional restrictions still deny the resource. The renderer obtains the body from `PolicyRuntime`, never from the profile, and uses Flutter `Text`, with no scripts, forms, active links or remote dependencies.

The only correction enables normal text wrapping. The existing production reader already wraps, so its default rendering stays intact with the empty registry. A controlled fixture simulates a legacy fixed-line renderer in a narrow viewport; applying its exact correction increases visible wrapped layout height, while an unreviewed sibling produces the policy-denial message. This is an actual rendering test rather than a profile-name assertion.

## Revocation and rollback

Within a registry lifetime, activation sequences must increase. Revocations accumulate and cannot be removed by a newer pack, nor can an older pack be replayed. Revocation, expiry or a body-digest change removes the correction; the default reader behavior resumes. No rollback can make a denied resource eligible. Policy changes trigger re-evaluation, and profile expiry invalidates the renderer.

The production registry starts empty after restart. There is no persistent correction-pack loader, automatic update job or signed correction endpoint. Durable checkpoint/restart/remote-distribution acceptance is therefore not claimed; those are prerequisites for any future production pack service. The current journal records only that a correction operation occurred if its caller instruments one; profile/resource/evidence IDs are excluded from receipts.

## Review and release evidence

A production correction needs a reproducible supported-resource defect, its exact approved content revision, a narrowly explained layout change, regression coverage for adjacent denied resources, review ownership/date, expiry and a revocation plan. A classification or resource-review request is a different workflow. Neither a report nor an “official” identity badge approves unknown content.

Tests live in `test/signature/compatibility_test.dart`, `privacy_journal_test.dart` and `privacy_export_widgets_test.dart`. The controlled fixture uses a synthetic signed policy bundle. No real prohibited site, user report, external endpoint or unreviewed production correction is used. Final application/platform evidence belongs in the shared acceptance matrix; passing schema and widget tests alone does not prove a live-site or provider integration.
