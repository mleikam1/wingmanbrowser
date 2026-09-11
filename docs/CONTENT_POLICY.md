# Content policy

## Mandatory baseline

Pornographic/sexually explicit entertainment; gambling/wagering; alcohol commerce/promotion; recreational-drug commerce/misuse promotion; tobacco/nicotine/vaping commerce/promotion; and known phishing, malware, scams and harmful downloads are permanently restricted. Identities, beliefs, ordinary language, and educational discussion are not category violations by themselves. There is no keyword-only blocking rule and no broad education/government-domain exemption.

`MandatorySafetyPolicy` is application code. Settings, private mode, PINs, administrative roles, payments, signed host lists, time limits and malformed legacy JSON cannot remove it. Unknown content is not presumed safe. The only present positive capability is `bundledPlainText`: exact reviewed resource ID, signed metadata, hash-verified UTF-8 body, approved context, current review window, supported policy version and nonrevoked sequence.

A record cannot authorize a network request. Navigation, assets, scripts, media, authentication, downloads, remote Reader and external dispatch are distinct operations, all unavailable in this milestone. Even an official source URL is provenance only. No host, suffix, category tag or role creates a live permission.

## Current coverage

Fourteen original articles cover science (5), creativity (2), learning (3), digital safety (2), outdoors (1), and general support (1). Source references were checked September 10, 2026. The articles are short development editorial content, not a production web database, comprehensive curriculum, clinical treatment, or an independent safety certification. References are rendered as inert text.

The source manifest identifies review date, expiry (March 10, 2027), development reviewer, CC0 license for original text, contexts, collection, asset path and provenance. Signing adds exact SHA-256 hashes, byte lengths and a content capability. Review applies to these bundled bytes. It does not cover a changing reference page.

Authoritative references include [NOAA tides](https://oceanservice.noaa.gov/facts/tides.html), [NASA Moon phases](https://science.nasa.gov/moon/moon-phases/), [USGS water cycle](https://www.usgs.gov/faqs/what-earths-water-cycle), [Library of Congress source analysis](https://www.loc.gov/static/programs/teachers/getting-started-with-primary-sources/documents/Analyzing_Primary_Sources.pdf), [National Park Service stewardship](https://www.nps.gov/articles/leave-no-trace-seven-principles.htm), [CISA phishing guidance](https://www.cisa.gov/sites/default/files/2024-09/Secure-Our-World-Phishing-Tip-Sheet.pdf), and [SAMHSA crisis support](https://www.samhsa.gov/find-support/in-crisis). No source endorses Wingman. Original activities clearly distinguish reference context from source-derived instruction.

## Verification and failure

The local repository verifies Ed25519 signatures, catalog size/hash/schema/version/sequence, record count, IDs, exact asset paths, contexts, review dates, expiry, revocations, content byte limits and each body hash. A durable monotonic sequence/time/revocation checkpoint prevents ordinary application rollback from undoing already observed policy state. A failed replacement retains a still-valid current snapshot. Missing/corrupt/expired policy or unavailable trust storage yields restricted Home. No error path converts to allow.

This is an immutable packaged catalog, not an operating remote update service. Production key custody, independent review, signed update distribution, revocation response, rotation, transparency, and authenticated recovery require further implementation and operational approval. App reinstallation, device compromise and OS backup restoration are not claimed to be defeated by a local SQLite checkpoint.

To sign a reviewed local development revision from the repository:

```sh
dart run tool/policy/sign_catalog.dart /absolute/path/outside/repo/development-policy-key.txt
```

The signer refuses a seed path inside the repository and does not print the seed. Do not ship the development seed, silently extend expired content, or treat a new signature as a completed human review. `catalog.source.json` is authoring input, not a runtime asset.

## Review requests

The UI explains the review boundary and requests minimal public-domain context through an established human contact. There is no connected submission inbox, automatic upload, temporary approval, crowdsourced grant or “open elsewhere” action. A real reviewed submission and appeal workflow is deferred. School-specific escalation requires a real configured school contact and pilot validation.
