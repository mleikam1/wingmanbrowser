# Official Routes review

Status: **Partial** overall. Local catalog search and evidence inspection are implemented. **Live opening is disabled pending review** because the authoritative policy permits reviewed bundled plain text only. No record in this catalog enables a website, redirect, sign-in, download, embedded resource, external browser, or active approval badge.

## What was reviewed

On **2026-09-11**, development research opened the primary sources below and checked the organizational links or publisher identity recorded in `assets/signature/official_routes.json`. Search results alone were not used as identity evidence. The catalog contains **18 real identities**, with English-language starting points for global organizations and explicitly labeled US, UK, and Canadian services. It is a small authored directory, not comprehensive support, government, software, or sports coverage. Results are local and unranked by payment; no precise location is inferred.

Each version-1 record contains organization, task, exact canonical HTTPS address and host, region/language, source evidence with an explanation, review time, expiry, revocation status, all six mandatory policy identifiers, and optional related local guide IDs. Review expires **2026-12-10 at 00:00 UTC**. This is an identity-review window, not a promise that a destination will remain safe or unchanged throughout it. The runtime uses the existing policy clock; its documented local-clock limitations still apply.

| Organization and task | Reviewed starting address | Primary identity evidence |
| --- | --- | --- |
| Apple — Product support and repair help (Global; choose country at destination) | [support.apple.com](https://support.apple.com/contact) | [Source](https://www.apple.com/contact/) |
| Microsoft — Product and account support (Global; choose country at destination) | [support.microsoft.com](https://support.microsoft.com/contactus) | [Source](https://www.microsoft.com/en-us/) |
| Adobe — Creative Cloud and Acrobat help (Global; choose region at destination) | [helpx.adobe.com](https://helpx.adobe.com/support.html) | [Source](https://www.adobe.com/about-adobe/contact.html) |
| Mozilla — Firefox browser download choices (Global; English starting page) | [www.firefox.com](https://www.firefox.com/en-US/download/all/) | [Source](https://www.mozilla.org/en-US/firefox/) |
| Mozilla — Firefox browser support (Global; English starting page) | [support.mozilla.org](https://support.mozilla.org/en-US/) | [Source](https://www.firefox.com/en-US/) |
| Google — Google Account and Gmail recovery guidance (Global; English starting page) | [support.google.com](https://support.google.com/accounts/answer/7682439?hl=en) | [Source](https://about.google/company-info/contact-google/) |
| Internal Revenue Service — Federal tax help and contact options (United States) | [www.irs.gov](https://www.irs.gov/help/let-us-help-you) | [Source](https://www.usa.gov/agencies/internal-revenue-service) |
| Social Security Administration — Replacement Social Security card information (United States) | [www.ssa.gov](https://www.ssa.gov/number-card/replace-card) | [Source](https://www.usa.gov/agencies/social-security-administration) |
| United States Postal Service — Change-of-address starting page (United States) | [moversguide.usps.com](https://moversguide.usps.com/mgo/disclaimer) | [Source](https://www.usa.gov/agencies/u-s-postal-service) |
| U.S. Department of State — Apply for a U.S. passport (United States) | [travel.state.gov](https://travel.state.gov/en/passports/apply.html) | [Source](https://www.usa.gov/agencies/u-s-postal-service) |
| Federal Trade Commission — Identity-theft reporting and recovery starting page (United States) | [www.identitytheft.gov](https://www.identitytheft.gov/) | [Source](https://www.usa.gov/identity-theft) |
| Annual Credit Report Request Service — Credit report request starting page (United States) | [www.annualcreditreport.com](https://www.annualcreditreport.com/index.action) | [Source](https://www.consumerfinance.gov/ask-cfpb/how-do-i-get-a-free-copy-of-my-credit-reports-en-5/) |
| HM Passport Office — Apply for or renew a UK passport (United Kingdom) | [www.gov.uk](https://www.gov.uk/apply-renew-passport) | [Source](https://www.gov.uk/browse/abroad/passports) |
| Government of Canada — Canadian passport services when applying in Canada (Canada) | [www.canada.ca](https://www.canada.ca/en/immigration-refugees-citizenship/services/canadian-passports.html) | [Source](https://travel.gc.ca/travelling/documents/passport) |
| National Park Service — Plan a national park visit (United States) | [www.nps.gov](https://www.nps.gov/planyourvisit/index.htm) | [Source](https://www.usa.gov/agencies/national-park-service) |
| The International Football Association Board — Association football laws of the game (International) | [theifab.com](https://theifab.com/laws/latest/about-the-laws/) | [Source](https://inside.fifa.com/refereeing/media-releases/var-decision-communications-trials-confirmed-by-the-ifab) |
| FIBA — International basketball rules information (International) | [about.fiba.basketball](https://about.fiba.basketball/en/our-sport/official-basketball-rules) | [Source](https://about.fiba.basketball/en/our-sport/official-basketball-rules) |
| National Football League — American football NFL rulebook information (United States) | [operations.nfl.com](https://operations.nfl.com/rules-officiating/2026-nfl-rulebook) | [Source](https://www.nfl.com/) |

## Identity and destination boundaries

The runtime accepts only a bounded exact HTTPS address. It rejects credentials, explicit ports, fragments, percent-encoded ambiguity, dot segments, backslashes, trailing-dot hosts, numeric hosts, and malformed labels. Unicode and punycode destinations are unsupported in this starter schema rather than being guessed equivalent. Alternate subdomains, appended paths, and changed queries do not inherit a review. A dedicated future IDN review would need canonicalization and displayed-identity evidence; this implementation does not claim universal IDN coverage.

Several verified publishers changed canonical routes: Mozilla links to Firefox.com; Google's contact page and recovery guidance use separate corporate/support hosts; IRS, State Department, Canada's passport portal, and NFL rulebook links redirect to newer paths. Their observed destination was separately checked and recorded. Runtime does **not** follow or approve arbitrary redirect chains. Marketing parameters were omitted only where the exact clean destination was independently opened. The Google recovery form's generated authentication URL was not retained. USPS and IdentityTheft.gov exposed application shells; no submission, charge, or authenticated workflow was tested. No credentials or personal government records were submitted.

Evidence establishes a claimed organizational relationship. It does not verify every claim, transaction, seller, document, or changing page. HTTPS alone is not identity evidence. The catalog's six policy identifiers are references, not category clearance. `OfficialRoute.assess` asks the authoritative policy; every current live result is denied. Expired, revoked, not-yet-reviewed, and incompatible records cannot be active. The screen offers no URL launcher, copy-and-launch flow, or external-browser fallback.

Related **Wingman guides** are original signed local articles, identified and labeled separately. Each guide is checked with the current policy, context, and additional restrictions before display and again before its callback. These articles do not reproduce the publisher's website or stand in for government/application instructions.

## Maintenance and trust

The JSON file is versioned and bundled with the application. This directory does **not** have a signed remote update service, remote revocation feed, or authenticated user-import path. App distribution supplies its present trust boundary; the schema validator cannot establish that arbitrary replacement bytes came from the original reviewer. A future common update pack must add signature verification, expiry/rollback protection, and reviewed publication. Signing metadata would not itself prove identity or content safety.

A maintainer should re-open primary organizational evidence and the exact destination, document any redirect/ownership change, check region and context, replace or revoke the record, and run the focused tests before shipping an updated application. Runtime review windows are capped at 180 days. Unknown schema versions, missing mandatory references/evidence, inconsistent hosts, duplicate identities, and catalogs over 128 KiB or 100 records fail closed. There is no live classification or eligibility pipeline for these records yet.

No support numbers, partnerships, endorsements, sports feeds, scores, or licensing rights were invented. The catalog contains authored descriptions and source links, not copies of rulebooks, government forms, courses, or publisher content. IFAB/FIBA/NFL source material remains subject to its publisher's terms; this directory grants no republication or download license. There are no paid rankings or affiliate links.

## Validation and remaining acceptance

`test/signature/official_routes_test.dart` checks all 18 records, exact scope, deceptive subdomains, credentials, fragments, ports, IDNs, altered queries/paths, expiry, revocation, malformed catalogs, and policy denial in normal/private and general/student contexts. The screen fixture checks local search, inspectable evidence, truthful empty results, and the absence of a live action. Root integration/runtime results are recorded in `FEATURE_ACCEPTANCE_TESTS.md` and `SIGNATURE_FEATURES_STATUS.md`.

Development source research used the web tool. **Wingman runtime catalog search does not request those sources.** The module contains no HTTP client, URL launcher, thumbnail or favicon request, review-submission endpoint, or query upload. Its journal events contain only typed activity/outcome categories. This is a source/runtime distinction, not a claim about every request the development browser made.

Live official-site opening acceptance remains disabled until a tested renderer/resource eligibility boundary exists. The current useful journey is: search an organization or task, choose the region, inspect the exact identity evidence, then optionally open a separately eligible Wingman guide. The review-request screen prepares a bounded local draft and explains that no submission service is connected; nothing is silently sent.

## Companion guide review (2026-09-11)

The signed bundled library now includes four additional original texts, bringing it to 18 articles under catalog version 1.1.0 / sequence 2. `measure-before-you-plan` and `plan-a-small-project` use the exact inch/foot facts checked against [NIST length guidance](https://www.nist.gov/pml/owm/si-units-length) and [NIST international-foot guidance](https://www.nist.gov/pml/us-surveyfoot). Their examples are limited to ordinary measuring/organizing, with no hazardous-work instructions.

`sports-notebook` and `fair-play-and-focus` contain original observation/reflection activities. The named values were checked in the [IOC Olympic Studies Centre's published interview](https://oscnewsletter.olympics.com/article/131/three-questions-to-ioc-president-thomas-bach_lang=en.html). The IOC values landing page and FAQ returned HTTP 502 to the research tool, so those unreadable pages were not represented as successfully reviewed evidence. No rulebook, training program, scores, schedules, Olympic branding, or publisher lesson was copied.

The existing fourteen signed resource rows and trusted public key are unchanged. The four new records have a 2026-09-11 review date; the existing records retain their dates and the catalog keeps its 2027-03-10 expiry. The development seed remains outside Git. `work/signature-catalog-sign.log` records signing without key output.

Focused verification: **24 module tests passed**, followed by **34 combined module and mandatory-policy tests passed** against the 18-article signed catalog (`work/signature-route-commit-final-tests.log`, `work/signature-catalog-and-modules.log`). Scoped analysis was clean (`work/signature-route-commit-analyze.log`). These are host tests, separate from root-owned native/web runtime validation.

Final focused follow-up: **38 tests passed** in `work/signature-domain-final-tests.log` (24 module cases, ten mandatory-policy cases, and four delayed-workspace navigation regressions). This run includes native `compute` dispatch and inactive selection masking. Scoped analysis was clean in `work/signature-domain-final-analyze.log`. It is host validation; device/web observations remain separately reported.

## UI handoff implementation

The updated Official Routes screen uses the shared Wingman page/status components, explicit purpose and region filters, and inspectable identity cards. Purpose grouping is a presentation mapping over the authored record IDs; it is not classification or eligibility evidence. There is still no live launch or active approval badge. Related guides remain separate and are rechecked before opening.

`RequestReviewScreen` starts with empty fields. It accepts a manually entered ASCII domain of at most 253 characters and an optional single-line reason of at most 500 characters / 2,000 UTF-8 bytes. It rejects URL paths, credentials, ports, numeric/IP forms, reserved local suffixes, IDNs/punycode, hidden direction controls and address/email-like reason text. These syntax checks do not establish ownership, registration or safety and cannot detect every personal detail.

The exact local draft is previewed before an explicit clipboard copy. No draft is persisted, no endpoint is contacted, and no request is marked submitted. Private drafts remain in memory; clipboard export is explicitly disclosed as leaving the private view, including possible access by other apps or clipboard sync services. Editing, route coverage and backgrounding invalidate the preview. A pending copy may already have reached the OS, so interrupted completion cannot promise that the clipboard remained unchanged; it is recorded as interrupted and no late success appears.

The journal stores only request-prepared/exported activity, outcome and destination category. It receives no domain or reason. New UI validation is recorded separately in the UI milestone QA rather than rewriting the earlier 0.5 test evidence above.

The UI handoff adds shared page/status components, purpose and region filters, and an adaptive evidence sheet. [O/C UI evidence](ui/OFFICIAL_COMMIT_QA.md) records the real Flutter light/dark captures and eight-width, 200%-text checks. These tests retain the disabled live action; they do not validate live browsing or OS clipboard behavior.
