# Content operating costs

Pricing checked September 11, 2026. USD figures below exclude tax and are estimates, not an invoice or a spending authorization. No paid provider was purchased and no production infrastructure was created or deployed.

## Current state

The selected NASA, NOAA and USGS publisher feeds require no API subscription fee for the scoped attributed public-domain text use documented in [source rights](CONTENT_SOURCES_AND_RIGHTS.md). Local development uses the existing computer. This means no new metered cloud service was provisioned; it does not mean the user's existing cloud account has a zero balance.

Read-only repository/cloud inspection found no dedicated licensed news integration. The current gcloud default remains an unrelated project. The existing Wingman-named project has unrelated Android/Web Firebase applications and does not contain this browser's package/bundle IDs. Its resources and account-wide free allowances must not be silently repurposed. See the historical [cloud inventory](CLOUD_COST_PLAN.md). A dedicated, explicitly approved content project would be required for the proposed production configuration.

## Proposed shared-feed service

The implemented deployment shape is a private Cloud Storage object, one scheduled **Cloud Run Job** for all publishers, and a separate **Cloud Run read service** that returns only the common public snapshot. Clients do not fetch the bucket or publishers directly. The service currently sends identity JSON: no application compression, CDN, image distribution or per-user snapshot is configured. Personal topic/source ranking stays local.

The reviewable [deployment templates and operator instructions](../backend/deploy/README.md) remain undeployed. The reader specifies minimum 0 instances, maximum 2, 1 vCPU, 256 MiB, concurrency 32 and 30-second request timeout. The writer specifies 1 task, 1 vCPU, 512 MiB, 300-second task timeout and zero platform retries. Every source has its own persisted due time/backoff. A 30-minute schedule creates 48 executions/day and 1,440 in a 30-day month: normally no more than 4,320 publisher requests for three feeds, excluding source retry behavior. Even executions where sources are not yet due have task startup costs.

| Component | Planning rate / allowance, USD `us-central1` |
| --- | --- |
| Cloud Run Job | $0.000018/vCPU-second + $0.000002/GiB-second; **60-second minimum for each started instance** |
| Cloud Run read service, request billing | $0.000024/active vCPU-second + $0.0000025/active GiB-second + $0.40/million requests |
| Account-shared Run allowances | Jobs: 240,000 vCPU-seconds / 450,000 GiB-seconds monthly; request services: 180,000 / 360,000 plus 2 million requests |

These are current list rates, without commitments. Startup/shutdown and overlapping requests affect billed instance time. [Cloud Run pricing](https://cloud.google.com/run/pricing), [billing behavior](https://docs.cloud.google.com/run/docs/configuring/billing-settings).

The Job calculation uses `sum(max(60, instance lifetime in seconds)) × (0.000018 + 0.5 × 0.000002)`. At the minimum, 1,440 × 60 = 86,400 vCPU-seconds and 43,200 GiB-seconds: **$1.6416/month gross compute**. If each task lives 300 seconds, the same example is $8.208. These calculations precede shared allowances and exclude distribution, storage, scheduling and tooling. The former 30-second request-billed $1.09 estimate does not apply to this Job configuration.

Scheduler lists $0.10 per job per 31 days with the first three jobs per billing account free. Use one schedule, not one per publisher. [Scheduler pricing](https://cloud.google.com/scheduler/pricing).

Cloud Storage Standard in the selected single region is about $0.02/GiB-month, with Class A operations $0.005/1,000 and Class B $0.0004/1,000. The private bucket must share the Run region. The reader caches the object in memory for 15 seconds per instance; a cache miss currently performs metadata lookup plus object download. Thus client request count is not identical to bucket read count. Measure cold-start and cache-miss operations, including both reads. A 1,440-write example is $0.0072 for Class A operations; object versioning, soft delete and retention choices change storage costs. [Storage pricing](https://cloud.google.com/storage/pricing).

## Measured response and traffic scenarios

A local GET of `/v1/snapshot.json` returned **52,486 uncompressed bytes**, 48 real publisher items, snapshot `93470a9470abea5c1f3d39bc592edd8f`, generated September 12 at 01:10:50 UTC. Headers contained `Content-Length: 52486`, no `Content-Encoding`, and `max-age=60, must-revalidate`. This was measured against the running read service; it is not a production latency or traffic measurement. Receipts: `work/live-content-cost-headers.txt` and `work/live-content-cost-snapshot.json`. Later item/credit additions will change the size.

Below assumes two full GET responses per active user per day for 30 days, all traffic billed at the first North America Premium internet-transfer tier of $0.12/GiB, **before allowances**. Other destinations differ; this service's outbound transfer uses Cloud Run networking, not public-bucket egress. [Network pricing](https://cloud.google.com/vpc/network-pricing), [Premium tier](https://cloud.google.com/network-tiers/pricing).

The read-service illustration separately assumes **0.1 billable instance-second per GET**, 1 vCPU, 0.25 GiB, and no overlap: `seconds × (0.000024 + 0.25 × 0.0000025) + requests × 0.40 / 1,000,000`. This is an unmeasured planning input. Replace it with aggregate billable time after a cloud load test; concurrency may lower it, while startup, GCS reads, retries and slow clients may raise it.

| Daily active users | Monthly GETs | Body transfer | Transfer gross | Read service compute + requests gross |
| --- | --- | --- | --- | --- |
| 1,000 | 60,000 | 2.93 GiB | $0.35 | $0.17 |
| 10,000 | 600,000 | 29.33 GiB | $3.52 | $1.72 |
| 100,000 | 6,000,000 | 293.29 GiB | $35.19 | $17.18 |

A 304 reduces body transfer but still uses request/compute resources. Headers, preflight/health requests, unbounded hostile traffic, deploy cache misses, builds, Artifact Registry, monitoring/log storage, DNS, and any future CDN remain additional costs. The current app allows manual refresh and therefore does not enforce this two-GET/day budget assumption. Source ingestion load remains independent of those refreshes.

## Required approval and operating evidence

Before production, select a dedicated project, billing account, region, traffic expectation and numeric budget with the owner; do not reuse the CLI default or the unrelated Wingman-named project. Approve public GET exposure and the final IAM identities separately from a publisher license. Review pinned image digests, private bucket generation writes, soft-delete/lifecycle decisions, alerts, aggregate monitoring and a service shutdown procedure. No source URL, client IP, browsing history, interests or device identifier belongs in application diagnostics.

Maximum 2 and minimum 0 help bound service usage; they do not impose a monetary cap. Apply a **service-level** maximum across revisions and inspect actual scaling after rollout. Google documents that maximum instances can be exceeded briefly; revision-only limits can also multiply across active revisions. [Maximum instance behavior](https://docs.cloud.google.com/run/docs/configuring/max-instances). Budget alerts notify rather than guarantee a hard spending stop.

Production sizing still needs measured Run billable instance time, request count/status, p50/p95 latency, startup count, instance count, bytes sent, 200/304 mix, GCS operations, Job lifetime/failure counts, oldest source validation, and snapshot item/byte counts. Use aggregated metrics without adding personal content. The templates, pricing formulas and local acceptance are reviewable; deployed cloud performance and a universal monthly total remain unverified.

## Paid broad-news decision

**Recommended licensing inquiry: Guardian Open Platform Commercial / negotiated fixed-term content subscription.** This is a direct publisher licensing route for journalism across broader topics. Its commercial access page lists custom quotas/throttles and price dependent on usage. The licensing team describes monthly-fee fixed-term subscriptions. **Current price is quote-only; there is no published numeric plan price to approve.** We have not requested a quote, contacted the publisher, created a key or signed an agreement. [Commercial plan](https://open-platform.theguardian.com/access/), [licensing FAQ](https://licensing.theguardian.com/frequently-asked-questions).

A quote must name the content fields, app/web distribution channels, territory/languages, refresh quota, excerpt length, source/byline requirements, cache/offline duration, reading-list treatment, withdrawn-item deadline and whether third-party photography or agency copy is included. Wingman requires no advertising, tracking, sponsored cards or automatic external moderation. The agreement must fit those constraints. Do not infer permission for image reuse or feed redistribution from API access alone.

For comparison, **NewsAPI.org Business currently lists $449/month billed monthly**, 250,000 requests/month and $0.0018 per excess request. Its pricing page offers a developer tier only for development/testing and no full-article content. More importantly, its terms leave third-party intellectual-property rights with their owners and prohibit using the service to republish copyrighted material without an applicable right. That subscription is **not sufficient evidence of Wingman's publisher redistribution rights** and is not selected. [Pricing](https://newsapi.org/pricing), [terms](https://newsapi.org/terms).

Approval still needed: a concrete publisher agreement and numeric quote for broad coverage, plus a dedicated production infrastructure plan with measured traffic assumptions. Authorized public-source development and acceptance can proceed independently. General news and sports remain coverage gaps until a licensed, tested provider is actually enabled.
