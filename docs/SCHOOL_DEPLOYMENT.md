# School deployment — first permanent-protection milestone

Wingman Student is an **ad-free product configuration**, not a claim of completed school deployment. Every edition keeps the same mandatory protection baseline. A manager may add restrictions or select already-eligible resources, but cannot approve prohibited/unreviewed content through a lower-priority allowlist.

## Actual scope and status

| Capability | Current milestone status |
|---|---|
| Compile-time student configuration | **Implemented and tested** for edition selection and commerce denial; selected by `--dart-define WINGMAN_EDITION=student`. Complete Student application acceptance remains unverified |
| Advertising | **Disabled pending review** across the product; student advertising is prohibited, not a future opt-in |
| Personal Wingman accounts | **Deferred**; basic local use does not require one |
| Managed-app configuration adapters and enrollment | **Deferred**; no existing Android/iOS adapter or enrolled test deployment is claimed |
| School administration/authentication/tenant isolation | **Deferred**; no admin backend, dashboard or school accounts |
| Discovery-session reset | **Implemented but unverified** until final UI results are recorded; clears current reviewed saves/tabs/searches and preserves additional restrictions. Private reset leaves normal saves intact |
| Complete shared-device school sanitation | **Deferred** pending management, file-provider and identity-provider acceptance; discovery reset is not a complete device wipe |
| ChromeOS/managed desktop extension | **Deferred**; Flutter Web is a companion, not an extension or device-wide filter |
| Real school pilot deployment | **Blocked** by an approved test management environment, enrollment authorization and school/provider agreements |
| External AI, marketing, student profiling | **Disabled pending review**; no such student service is implemented |

An invalid edition value is unknown and receives noncommercial, restrictive behavior. Edition selection is build configuration, not authenticated enrollment. No build flag can remove mandatory protection.

No school deployment is performed in this milestone. No real device is silently enrolled, no school account is created, and no production cloud resource is provisioned.

## Smallest useful managed pilot

The proposed first target is one managed Android app on an explicitly authorized test device/profile. Keep the management system external; do not build a new DPC/EMM platform.

Use Android's managed-configuration schema and `RestrictionsManager`. Read configuration before restoring content, recheck on resume and dynamically register for configuration-change broadcasts. Missing XML defaults are not guaranteed to appear in the runtime Bundle. Validate types, bounds and schema versions; invalid configuration must not open unknown content. [Android managed configurations](https://developer.android.com/work/managed-configurations)

The initial schema should contain only additional restrictions, approved collection IDs, approved classroom bookmark IDs, local session policy and non-sensitive configuration/version health. It must contain no baseline-off switch, arbitrary allowlist, external browser escape, advertising enablement, search template or credentials. Catalog IDs must resolve through Wingman's authoritative policy; a school-provided URL is not automatically eligible.

Only trusted OS-delivered managed configuration or a separately authenticated/signed enrollment may supply institutional settings. A public school identifier, query parameter, local PIN or student login is not administrator authorization. Sign-out must leave managed restrictions in force.

Acceptance must exercise actual DPC/EMM delivery, changes while running, malformed/missing configuration, restart, sign-out, attempted edition switching and attempted core-policy relaxation. An injected fixture or sample XML can verify parsing but cannot establish real enrollment, tenant authorization or device management.

Apple supports managed app configuration and the ManagedApp framework, with legacy configuration compatibility. A later iOS pilot needs a managed app, approved signing/distribution, an enrolled device and actual configuration-delivery tests. An iOS simulator compile does not prove MDM support. [Apple managed configuration](https://developer.apple.com/documentation/devicemanagement/configuring-managed-apps-and-extensions), [configuration validation](https://developer.apple.com/documentation/managedapp/specifying-and-decoding-a-configuration)

Chrome's enterprise force-install policy applies to real extension artifacts on supported managed browsers. No Wingman extension exists here, and ChromeOS support is not established by loading Flutter Web. [Chrome enterprise policy](https://chromeenterprise.google/policies/extension-install-forcelist/)

Preventing use of another app or removal of protection requires appropriate device-management/network controls and separate verification. Wingman protects only its supported surfaces; it cannot enforce policy across an unmanaged device.

## Shared-device release gate

A school session lifecycle must stop loads and pending callbacks before clearing student state, wait for actual native completion, and preserve institutional policy separately from session data.

Tests must cover normal/private cookies, authentication, localStorage/IndexedDB/cache/service workers, history, tabs, suggestions, student-created library entries, downloads and pending export/share files. Classroom-provisioned bookmarks require a separate ownership boundary. A timeout must keep the next session unavailable rather than announce successful cleanup.

The current product renders only bundled reviewed text. Startup quarantines old navigation metadata and clears legacy native website state before content is shown; the old live-browser clear-data UI is retired. Student reviewed saves and additional restrictions are session-memory only. The discovery reset does not erase quarantined historical records or completed downloads. OS password managers, files deliberately exported to another app, school identity providers and network logs remain outside complete Wingman deletion control. These limits must be visible to schools before deployment.

## Student-privacy review checklist

These are review gates, not legal approval or certification:

- **COPPA:** determine applicability and audience; review the amended rule, notice, authorization, access/deletion, security and purpose-limited retention. School authorization applies only to educational use; the operator remains responsible. A PIN or adult checkbox does not supply consent. The 2025 amendments' general compliance date was April 22, 2026. [FTC guidance](https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions), [official rule publication](https://www.govinfo.gov/content/pkg/FR-2025-04-22/pdf/FR-2025-04-22.pdf)
- **FERPA:** identify education records and the appropriate legal basis; if using the school-official exception, assess institutional function, direct school control, legitimate educational interest and redisclosure restrictions. Document school/vendor responsibilities and contracts. [Education Department regulations](https://studentprivacy.ed.gov/ferpa)
- **CIPA:** assess the institution's filtering, safety-policy, public-notice, education and monitoring obligations. A browser is not the school's complete internet-safety program; do not add covert URL logging to claim compliance. [USAC CIPA requirements](https://www.usac.org/e-rate/applicant-process/starting-services/cipa/)
- **State law:** map the actual district/student jurisdictions with qualified counsel. California's current student-information statute illustrates additional restrictions on commercial uses and covered student information; it is not a nationwide checklist. [California BPC §22584](https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=22584.)
- **Platform policies:** declare audiences accurately; review Apple child/Kids Category and Google Play Families requirements. Student ad prohibition remains stricter than limited platform exceptions. [Apple §1.3](https://developer.apple.com/app-store/review/guidelines/#kids-category), [Google Families](https://support.google.com/googleplay/android-developer/answer/9893335)
- **Accessibility:** test screen readers, keyboard use, large text, contrast and reduced motion. Assess the school's ADA/other obligations and current timelines; DOJ's guidance reflects 2026 deadline amendments. No accessibility conformance certification is claimed. [DOJ public-entity guidance](https://www.ada.gov/resources/web-rule-first-steps/)
- **Operations:** document minimal data categories, purpose/retention/deletion, processors/subprocessors, provider-visible metadata, notices, school agreements, incident response, vulnerability handling and least-privilege access. Qualify every third-party login/provider claim with tested device/site combinations.

No default dashboard of student URLs, search terms, sensitive blocks, screenshots or keystrokes is planned. Review requests require minimal disclosed data and an approved school workflow; no reporting inbox is connected.

## Cloud and deployment boundary

No Browser Firebase app, school tenant service, policy-hosting endpoint, sync service or AI endpoint is configured. Existing authenticated tooling is not infrastructure approval. Common signed artifacts and local decisions remain the preferred future distribution architecture; ordinary browsing must not become a per-navigation Wingman service request.

If a backend is later approved, require real authentication/authorization, tenant isolation tests, server-side credentials, bounded quotas, reviewed logging/retention and separate development/production environments. Billing alerts are not an enforceable spending cap. No resource is deployed or school service price published here.
