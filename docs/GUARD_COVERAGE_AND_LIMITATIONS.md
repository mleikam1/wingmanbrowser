# Guard coverage and limitations

**Category filtering is experimental.** The shipped data is a small development starter, not a maintained comprehensive category or threat feed. The user chooses boundaries; unknown destinations are not evidence of safety. A successful synthetic test establishes enforcement behavior, not real-world coverage.

| System | Current data and behavior | Limits |
| --- | --- | --- |
| Optional categories | 49 total manually authored category/support/threat-fixture records in one signed global pack | Many sites are unclassified; domain-level classification cannot distinguish every page on mixed-purpose sites |
| Known threats | Shipped malware/phishing/download records are synthetic `.test` fixtures only | No production Wingman threat feed or Google Web Risk integration; native engine security remains separate |
| Native security | Android Safe Browsing and WebKit security/fraud warnings where available; invalid TLS is cancelled | Provider, region, engine version and website behavior affect coverage; HTTPS is not proof of trustworthiness |
| Tracking | Seven selected EasyPrivacy third-party domain rules | Limited starter; no comprehensive tracker guarantee; Android counters available, no invented iOS count |
| Custom hosts / Focus | Local exact/suffix rules, temporary Focus and tab-scoped exceptions | Browser-only; other apps, alternate browsers, app deletion and device control are outside this boundary |
| SafeSearch | Recognized DuckDuckGo, Google `.com`, Bing and Brave GET searches | Other providers, regional domains, POST searches and result destinations may not be covered |
| Support and education | Explicit curated support rules can exempt optional category matches | Never exempt known threats, custom blocks or invalid TLS; not automatic medical classification |

## Provenance and maintenance

The category starter's factual selections were independently authored and released under **CC0-1.0**. The tracker subset comes from EasyPrivacy under **CC BY-SA 3.0**; its attribution and license remain bundled. See [category provenance](../assets/guard/README.md), [tracker attribution](../assets/guard_tracking/ATTRIBUTION.md) and [signed distribution format](GUARD_FILTER_PACKS.md). Referenced source URLs are provenance, not startup requests or partnerships.

The app ships a development public verification key. Its signing seed is outside the repository. Production release requires licensed maintained data, protected production signing, key rotation, an operational owner and a reviewed global HTTPS artifact endpoint. **No endpoint is configured.** Locally stored verified data remains available offline. Corrupt updates must retain the last valid generation, and an unavailable local store must visibly report unavailable category coverage.

Classification uses normalized hosts and indexed suffix queries. It does not use URL keyword matching, hidden browsing profiles, sensitive inference or per-navigation Wingman cloud requests. Reports are explicit local previews followed by a chosen copy/share action; no reporting inbox is active.

## Phase 3 boundaries

Milestone 3A fixes the current browser and privacy boundaries. Stronger commitments, scheduled restrictions, Help Now and broader maintained filter sources belong to 3B and remain **Deferred**. Existing short Focus sessions and Family PIN are not a claim that those new commitment/recovery features exist.

Owned ad eligibility is evaluated locally before consent or SDK work. Unknown/strict protection requirements withhold the current provider because it cannot establish compatibility with those choices. Settings, block pages, security warnings and private pages stay ad-free. See [monetization policy](MONETIZATION_POLICY.md).

For exact tested navigation paths and outstanding native gaps, use [Phase 3 status](PHASE_3_STATUS.md) and [platform matrix](PLATFORM_CAPABILITY_MATRIX.md). Emulator/simulator tests do not establish physical-device or every-version behavior.
