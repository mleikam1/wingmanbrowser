# Before You Commit: supported scope and limits

Status: **Implemented and tested for bounded local text analysis**; live-page extraction is **disabled pending review** with the existing live-web renderer. This is a deterministic English evidence locator, not a contract interpreter, merchant verification service, or purchasing agent. It makes no network request and requires no AI, account, provider key, or paid service.

## The usable journey

Open Before You Commit, paste visible text you choose, enter a short source label, choose its language, and inspect the selection before pressing **Check this selection**. The in-app practice example is prominently labeled as invented terms. An action on an eligible Wingman article can also supply that article; the screen resolves its ID back to the current signed catalog instead of trusting a caller-supplied body. Those educational articles may contain none of the requested commercial terms, which correctly yields unavailable findings.

The six topics are trial duration, recurring charges, billing frequency, cancellation, returns/refunds, and seller/service identity. Findings show up to three **exact source excerpts**, their selected-text heading and original line number, the source label/type, and a local check timestamp. A seller named in text is explicitly unverified. Missing evidence never means favorable terms. There is no “Safe to buy” or blanket merchant/contract approval.

The screen labels directly stated wording, potential conflict, and unavailable evidence. It does not create inferred conclusions. Distinct prices, trial durations, billing intervals, and selected contradictory refund phrases produce a potential-conflict warning. Different options may explain these differences; the tool does not choose one as authoritative or calculate an effective total. Synonyms, nuanced qualifications, region-dependent law, exclusions in linked pages, and many contradictions can be missed. It is not legal or financial advice.

## Input, privacy, and storage

Native extraction is dispatched through Flutter `compute` to a separate isolate. Flutter web uses its current event loop with the same small limits; it does not claim a worker or unrelated-tab access. Obsolete results are discarded rather than displayed.

Input is explicitly user-selected plain text: at most **24,576 UTF-8 bytes and 500 lines**, with a 120-character source label. Raw HTML/form/script markers and control characters are rejected. No DOM, field values, cookies, website storage, other tab, hidden content, linked terms, file, or clipboard is read automatically. Pasting is a user operation. Cloud analysis, automatic crawling, sending messages, submitting forms, credentials, purchases, and cancellation actions do not exist in this module.

Users are told to omit personal and account information. Recognized password/token/cookie/payment-identifier lines are removed before extraction and fingerprinting; the report states the omitted count. Detection is conservative and incomplete: unlabelled secrets, names, addresses, and other personal information may still be present in text the user supplies. It is **not** a general personal-data scrubber. The input remains visible for review and is never automatically saved. Unsupported/long passages are not silently summarized into a conclusion.

Findings are transient by default. **Save analysis locally** requires explicit confirmation describing the retained fields. The shared consumer workspace stores only the bounded report: excerpts/sections, source label/type and optional approved ID, check time, fingerprint, statuses, and warnings. It does not receive the full input. Each report is validated under schema 1, capped at 32 KiB, six unique topics, three 500-character excerpts per topic, and twelve bounded warnings. The root workspace currently permits eight saved reports and enforces its aggregate document limits and durable writes. The reusable screen also bounds an injected saved-list callback to at most twenty candidates. A save is called completed only after the shared callback succeeds; errors stay failed with sanitized text. Delete also requires a clear choice and completes through the shared callback.

Private analysis never reads the normal saved-report callback and never invokes either save or delete callback. Its journal instance is scoped by the root to the private session. The current root also suppresses saved-analysis controls for student/other ephemeral contexts; their other feature state uses a separate memory workspace. App files and OS backups follow the existing local-storage policy; saving is not forensic secure deletion or an encryption claim. Report snapshots are local user data, not signed attestations. A timestamp records the device's check time and does not prove the original page was current.

## Changes, uncertainty, and untrusted text

Editing the selection invalidates its report immediately. A generation check rejects delayed results after editing, route changes including a rapid push/pop, backgrounding, or disposal. An expired/revoked approved article is rechecked before analysis, rendering, and save; its source text is removed and saved excerpts are hidden when it becomes ineligible. The caller supplies additional restrictions and current context; they cannot grant mandatory-policy exceptions.

Historical saved findings are clearly labeled snapshots, never claims about today's terms. Paste current terms to analyze again. The app cannot observe changes to an unrelated browser tab, a dynamic website, a seller's backend, or a linked document. There is no supported live page state to refresh in this milestone.

English is the only supported extraction language. The user selects English or another language/unsure; known unsupported scripts are also rejected for extraction. This is not a universal language detector. Another language/unsure yields unavailable findings without translation. Dollar symbols do not imply USD; ambiguous symbols and comma/decimal formatting remain verbatim with warnings. Supported currency-code patterns cover USD, EUR, GBP, CAD, AUD, NZD, JPY, CHF, and INR, without exchange-rate or location assumptions. Billing synonyms and options can produce conservative false conflicts.

Page-like text is data. There is no instruction interpreter, tool executor, native bridge, or action dispatcher. Embedded “ignore instructions” text cannot ask the app to access another tab, send data, alter policy, or manufacture a finding. The extraction rules themselves are intentionally limited and can match incomplete phrases; the displayed excerpt, not a fabricated paraphrase, is the evidence.

## Evidence and observability

The focused core suite covers clear/missing/conflicting terms, unsupported language, ambiguous currencies/decimals, missing cancellation methods, sensitive-line omission, hostile instructions, changed selections, malformed saved data, and input/evidence bounds. Widget regressions cover private isolation, explicit save/delete and failed durable callbacks, delayed result cancellation, canonical approved article resolution, and policy revocation. Exact commands/results are recorded in the milestone acceptance document.

The Privacy Journal receives typed `localAnalysis`, `analysisSaved`, and `analysisDeleted` events with actual started/completed/failed/canceled outcomes and a local destination. It does not receive the text, source label, source ID, fingerprint, excerpts, query, or prices. This instrumentation covers Wingman-owned actions; it is not a complete network trace or a claim that the operating system collected nothing.

Native background extraction or cloud enrichment is not secretly substituted on an unsupported platform. The same bounded pasted-text function works in the web companion. Live extraction, authenticated-page inspection, automatic linked-terms review, multilingual interpretation, production merchant verification, and legal/financial conclusions remain outside this supported scope.

Focused command: `flutter test --no-pub test/signature/official_routes_test.dart test/signature/commit_review_test.dart test/signature/route_commit_screens_test.dart` passed all **24 tests** on the host in the recorded run. The analyzer was clean. Logs are `work/signature-route-commit-final-tests.log` and `work/signature-route-commit-analyze.log` in the parent workspace. The later signed-catalog validation included these same cases and ten mandatory-policy cases (34 passed); it does not substitute for actual device network/performance testing.

Final focused follow-up: **38 tests passed** in `work/signature-domain-final-tests.log` (24 module cases, ten mandatory-policy cases, and four delayed-workspace navigation regressions). This run includes native `compute` dispatch and inactive selection masking. Scoped analysis was clean in `work/signature-domain-final-analyze.log`. It is host validation; device/web observations remain separately reported.
