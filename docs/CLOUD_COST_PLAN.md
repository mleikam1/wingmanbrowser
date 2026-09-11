# Browser cloud, privacy and cost plan

Reviewed September 11, 2026. This is the infrastructure decision for restoring protected visual browsing. It records an actual read-only account inventory and a deployment proposal; it does not claim that a Browser backend, remote updater or paid classifier has been deployed.

**Build the browser on the device first. New Firebase/Google Cloud infrastructure is not needed for native rendering, local policy decisions, tracker blocking, Launchpad, Spaces, or bundled artwork.** Ordinary page and permitted image requests should go to the requested website through the protected native path. Wingman should not operate a browsing proxy or upload pages for routine classification.

## Verified access and existing resources

Both installed CLIs authenticated successfully for project listing. Account identifiers, credentials and unrelated application names/configuration are excluded from this repository document. Listing access is not evidence of permission to administer every resource.

The existing Wingman-named project already has **billing enabled and unrelated applications**. The repository's Android ID is `com.wingmanbrowser.wingman_browser`; its iOS ID is `com.wingmanbrowser.wingmanBrowser`. Neither was present in the Firebase app inventory.

| Read-only check | Actual result |
|---|---|
| Current gcloud default | An unrelated project; unchanged. Project-scoped inventory commands specified the Wingman-named project explicitly |
| Firebase apps | Existing unrelated Android and Web apps; no Browser registration |
| Firebase Hosting | Existing default site associated with that Web app; not a vacant Browser destination |
| Functions | Existing second-generation functions serving unrelated workloads; no function invoked and no actual usage/cost established |
| Firestore | Existing default native database; no documents queried |
| Cloud Storage | Existing Functions source/upload buckets; no objects opened or downloaded |
| Enabled service metadata | Hosting, Firestore, Functions, Cloud Run, Storage and several other services already enabled; none enabled or disabled by this task |
| Direct Cloud Run service inventory | Unavailable: the installed gcloud runs on Python 3.9 and its Run command failed to load. Firebase's Functions metadata inventory succeeded; independently deployed Run services remain uninventoried |
| Repository integration | No Firebase configuration files or Firebase SDK dependency found at the audit start. The existing optional `HttpsFilterPackUpdateSource` has no instance configured in startup |

Commands used were project/app/site/function/service/bucket/database list operations and the project's billing-enabled flag. No function was invoked, application record inspected, credential value requested, IAM policy changed, API enabled, billing link changed, project created, service deployed or existing workload modified. CLI listing is not a billing statement: existing account spend and budgets were not audited, and **$0 incremental Browser service architecture does not mean the user's existing cloud bill is $0**.

Do not repurpose the existing Hosting site, database, functions or project-wide cost controls for Browser. If distribution later needs a cloud project, give Browser its own explicitly selected project and separate test/production release authority. This avoids charging Browser against another app's free allowance or interrupting unrelated apps with a budget response.

## Initial implementation: no new cloud dependency

| Capability | Chosen cost/privacy boundary |
|---|---|
| Page layouts, text and images | Maintained native engine plus enforceable local navigation/resource rules. No Wingman server hop per page |
| Required content rules | Versioned local policy, current reviewed scope and fail-closed unsupported operations. A cloud connection never becomes a prerequisite for keeping mandatory rules enabled |
| Trackers | Locally packaged, attributed data compiled to the native engine's supported semantics. No resource-URL telemetry to count blocks |
| Home discovery and collections | Explicit local preferences and bounded bundled artwork. No recommendation service, behavior profile, remote favicon service or automatic image hotlinking |
| Favorites, Spaces, themes and private sessions | Existing local stores and separate ephemeral private state; no Firebase Auth or database requirement |
| Product analytics and crash uploads | No new Analytics, Crashlytics, replay, ad or attribution SDK |
| Content classification | No Web Risk, Cloud Vision, Gemini or Vertex AI request in the ordinary browsing path |

This removes new metered server compute, inference, database reads/writes and Wingman-served page-image bandwidth from the initial design. App distribution, users' network plans, human content review and maintenance still have costs. Bundling assets is a privacy and serving-cost decision, not a reason to weaken the content policy or claim all dynamic pages are safe.

Cloud Vision SafeSearch returns likelihoods for adult, spoof, medical, violence and racy content. It is not a classifier for every Wingman rule, and using it requires sending image bytes or an image address to Google. We have not called it. An on-device model would also need measured category coverage, licensing, adversarial testing and a pre-display integration; describing a model is not implementing a reliable gate. [Vision SafeSearch](https://docs.cloud.google.com/vision/docs/detecting-safe-search), [Vision pricing](https://cloud.google.com/vision/pricing)

## Smallest future shared-update service

Use static distribution only when app releases cannot meet the required policy freshness. The following is a proposal, not currently active runtime behavior:

1. Build one common, signed manifest and immutable versioned bundles containing licensed rules, provenance, checksums, schema/minimum-app version, expiration and monotonic sequence. Validate on device before atomic activation. Keep the last valid bundle while rejecting expired or unsupported permissions; failure never switches the browser to unrestricted access.
2. Put signatures and immutable artifacts on static hosting. A small Firebase Hosting site can serve ordinary HTTPS files without adding a Firebase client SDK. Cloud Storage is an alternative when its measured storage/operation/transfer costs fit. Do not add Firestore, Cloud Run or App Hosting just to return a file.
3. Package initial rules and artwork in the app. Update checks should be common across users, at most daily with jitter, bounded time/bytes/retries, and local backoff. Fetch a bundle only when its verified version changes. Implement and test conditional requests before claiming bandwidth savings: the existing optional transport currently accepts a bounded HTTP 200 response, refuses redirects, and does not implement ETag/304 caching or an automatic schedule.
4. Use the same paths for everyone. Never include visited hosts, searches, selected topics, page text, screenshot bytes, PIN state, private-mode flags, account IDs or stable installation IDs in update requests. Category-specific download paths can disclose interests even without a user ID.
5. Keep publisher credentials and private signing material out of the app, repository and public files. Separate publishing authority from public download access. Use least-privilege short-lived release credentials and a reviewed production signing/key-rotation process; developer fixtures are not production trust.
6. Retain only necessary immutable releases, set deliberate cache and content-type headers, cap artifact sizes, and test rollback, outage, expired data, tampering and exhausted hosting quota. Select log fields/retention before activation. A common update still exposes IP address, time and requested artifact to the serving provider; it is not anonymous traffic. A future Run endpoint would have request logging by default unless deliberately configured. [Cloud Run logging](https://docs.cloud.google.com/run/docs/logging), [Firebase privacy](https://firebase.google.com/support/privacy)

No future updater should fetch at every tab open or page navigation. No paid AI fallback should activate when a local decision is uncertain. Unknown content stays bounded by policy while coverage is reviewed.

## Pricing and controls checked against current provider documentation

Prices below are public USD list-price observations, not a quote or an allowance verified for this account. Free usage can be shared with other workloads and can change.

| Service | Current finding and cost decision |
|---|---|
| Firebase Hosting | Pricing lists 10 GB storage and 360 MB/day data transfer at no cost, then Blaze rates of $0.026/GB storage and $0.15/GB transfer. The Hosting guide separately describes the transfer allowance as 10 GB/month. Use the conservative daily threshold for sizing and verify the actual project console before launch; do not promise free monthly transfer from a bursty release. [Pricing](https://firebase.google.com/pricing), [Hosting quotas](https://firebase.google.com/docs/hosting/usage-quotas-pricing) |
| Spark versus Blaze | Spark Hosting can stop serving after quota/grace is exhausted; Blaze incurs overage. Hosting allowances are project-wide and cached CDN delivery still counts as transfer. A separate Spark-only distribution project is an option if interruption is acceptable and the app handles unavailable updates safely. Existing billing-enabled workloads must not be downgraded for this purpose. [Hosting quotas](https://firebase.google.com/docs/hosting/usage-quotas-pricing) |
| Cloud Storage for Firebase | Requires the billing-enabled Blaze plan, including default buckets; available no-cost usage is not the same as a no-billing plan. Choose it only for a demonstrated need. Storage, operation, retrieval, replication and transfer charges vary by configuration. [Storage billing requirement](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024), [Cloud Storage pricing](https://cloud.google.com/storage/pricing) |
| Cloud Run / Functions | Not needed for shared static bundles. If a future dynamic operation is justified, start with zero minimum instances, request-based billing and a small reviewed maximum, bounded requests/retries and no unneeded background jobs. Instance limits reduce exposure but do not cap total monthly requests, transfer, logs or other services. [Run pricing](https://cloud.google.com/run/pricing), [Maximum instances](https://docs.cloud.google.com/run/docs/configuring/max-instances-limits) |
| Web Risk | Not enabled for Browser. Lookup sends URLs and currently includes 100,000 monthly calls, then $0.50/1,000 in the published next tier. The Update API's diff calls are free, but threat confirmations are listed at $50/1,000; a locally downloaded list therefore does not mean free protection at scale. Mixing APIs also changes the published billing treatment. [Web Risk pricing](https://cloud.google.com/web-risk/pricing), [Lookup behavior](https://docs.cloud.google.com/web-risk/docs/lookup-api), [Update behavior](https://docs.cloud.google.com/web-risk/docs/update-api) |

**Alerts-only budgets do not stop spend.** Google now also documents a separate **Preview** spend-cap option for one project and one eligible service: Gemini API, Agent Platform, Cloud Run or Run functions. Enforcement is delayed, in-flight work finishes, overages remain billable, and ongoing fixed storage/compute costs can continue. Hosting/Storage are not listed among those covered services. No cap was created or verified for this account. If a supported dynamic service is added later, use the actual spend-cap option where available, below the owner's chosen ceiling, alongside quotas and alerts; do not describe it as an instantaneous whole-project hard limit. [Alerts-only budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets), [Spend-cap scope and limitations](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps)

### Bandwidth sizing before a future deployment

Illustration only, using decimal units: 30 checks/month at 20 kB each plus four changed 2 MB bundles is **8.6 MB per active client per month**. This yields 8.6 GB for 1,000 clients, 86 GB for 10,000, or 860 GB for 100,000. It excludes headers, new installs, retry traffic, hotlink abuse and other hosted assets. A rollout can exhaust a daily allowance even when the monthly total looks small.

By comparison, loading twenty 200 kB Home images afresh each day adds 120 MB/client/month, or 120 GB at only 1,000 clients. These are arithmetic examples, not measured app traffic. Bundle a small reviewed image set and cache deliberately; do not start a per-user image generation or resizing service for Home. Recalculate with measured compressed artifacts, active clients, release cadence and provider billing units before enabling paid distribution.

## Data licensing and coverage

EasyList/EasyPrivacy allow GPL 3-or-later or CC BY-SA 3.0-or-later for the repository's covered data. Wingman's separate EasyPrivacy adaptation uses CC BY-SA 3.0 with attribution and identified modifications. Preserve provenance, the chosen license and ShareAlike obligations for adapted data. Externally referenced lists can have different terms. Translate only supported rule syntax and test exceptions/resource semantics; silently broadening a rule is not faithful conversion. [Author licensing statement](https://easylist.to/pages/licence.html), [Existing attribution](../assets/guard_tracking/ATTRIBUTION.md)

DuckDuckGo Tracker Blocklists and Disconnect's published list use noncommercial ShareAlike terms and offer separate commercial licensing. They were not copied or subscribed to by this cloud task. Their public availability does not establish redistribution rights for a commercial browser. [DuckDuckGo license](https://github.com/duckduckgo/tracker-blocklists#licensing), [Disconnect license](https://github.com/disconnectme/disconnect-tracking-protection)

Tracker data does not provide all prohibited-content categories or image classification. Any broader category feed needs explicit redistribution/offline rights, freshness/expiry requirements, measured false-positive/false-negative coverage, provenance and an affordable maintenance contract if commercial. Likewise, a website's permission to display its images in a browser is not permission to rehost those images as Wingman promotional artwork. Keep Home asset attribution/licenses separate from page navigation scope. No feed purchase, image license, provider partnership or universal filtering guarantee is claimed here.

## Deployment acceptance

The current decision is **no new cloud deployment and no new metered runtime service**. A later distribution release needs an identified Browser project, real measured artifact sizes and daily traffic, confirmed provider terms, production signing and rotation, tested update-failure behavior, provider-log disclosures, a project-specific cost ceiling and appropriate quota/budget controls. Existing unrelated services remain intact. This cloud plan is not a substitute for the native browsing and content-policy acceptance evidence.
