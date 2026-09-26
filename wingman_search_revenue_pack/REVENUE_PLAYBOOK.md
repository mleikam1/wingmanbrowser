# Revenue plan: earn money without selling users
All commercial rates and scenarios below are planning examples, not provider guarantees or predictions of Wingman revenue.

## The business in three parts
Organic supply: Wingman pays Brave for useful search results.
Distribution/product: people choose Wingman because the browser/search is helpful, fast, comprehensible and protected.
Paid demand: advertisers separately pay for labeled contextual search results and first-party sponsor inventory.

Search quality alone does not create the advertiser relationship. A standard Brave API account is not a revenue account. Build direct-campaign operations while investigating a privacy-compatible demand contract; do not promise turnkey search ad fill before one is signed.

## Launch sequence
### Gate A — permitted product and controlled cost
Build the prototype on the existing Flutter/Python stack. Confirm public branded use and relevant storage/image/ad rights. Use server-side secrets, no stored user queries, mandatory content checks and hard dispatch-level cost ceilings. Get a useful All/News experience before introducing more expensive verticals or automatic AI.

### Gate B — sell a small deliverable pilot
Prioritize advertiser categories that match Wingman's product and rules: productivity tools, password managers, learning products, ordinary consumer goods, office/home products and outdoor products. These are prospect categories, not existing advertisers. Exclude bypass tools, prohibited substances, gambling, sexual material, exploitative offers and other restricted promotions. Avoid sensitive personal-query monetization.

Prepare a functioning demo, exact placement specs, privacy explanation and honest dated aggregate traffic. Seek two or three small founding campaigns or one approved demand partner. Direct selling is a bridge to revenue, not an assumption that advertisers arrive automatically. Work with an approved agency/sales partner if direct selling is impractical; that relationship needs commercial terms and cannot weaken privacy.

A $500 package at $10 CPM needs 50,000 qualifying impressions. Three such packages need 150,000 impressions, not merely 150,000 page loads. A $500 CPC balance at $0.50/click funds at most 1,000 valid clicks; delivery depends on relevant query volume and real user choices. Smaller measured traffic requires smaller packages. Do not promise exact delivery timing without evidence. Bill only as agreed, provide credits/refunds for underdelivery, and track unearned prepaid money separately.

### Gate C — first earned revenue
One real approved paid campaign must actually deliver valid events; aggregate reports and payment/business ledgers must reconcile. Sample ads, house ads and an integration screenshot do not meet this gate. Sponsored publisher content is not counted as Wingman revenue unless Wingman has a real payment agreement for it.

### Gate D — prove contribution before scale
Run a bounded pilot and measure repeatable net earned revenue against provider and other actual delivery costs. A proposed growth threshold is at least four weeks of positive contribution with >=25% contribution margin, known refunds/invalid traffic, and adequate cash to pay provider costs before advertiser payouts arrive. This is a decision rule, not a claim of profitability or a promise that four weeks produces enough data.

Do not finance unlimited search traffic with an assumed future sponsor. Constrain pilot enrollment/spend rather than breaking current users' searches constantly. Keep the public product free; the business limits spending behind the scenes instead of adding a subscription tier.

## Search economics
Define S as all user-requested search result pages in the period, including noncommercial searches. f is the fraction with one eligible, filled ad opportunity; t is valid clicks per those opportunities; p is net earned Wingman revenue per valid click. Net means deductions expected from partner share, invalid traffic/refunds and payment costs are accounted for once.

Search revenue per 1,000 S = 1,000 × f × t × p.
Search provider cost per 1,000 S = paid calls per S × provider cost per 1,000 calls.
Search contribution = search revenue − provider cost − other variable search costs.

Assume 1.05 paid organic calls per S, a $5/1,000 provider rate and $1.25 other variable cost per 1,000 S. Delivery cost is $6.50 per 1,000 S. This excludes fixed overhead, separate news delivery/licensing and customer acquisition, all of which must be added to company profitability analysis.

| Assumption/result | Weak | Working case | Strong |
|---|---:|---:|---:|
| Fraction of all search pages with one ad | 30% | 50% | 65% |
| Valid click-through rate | 2% | 3% | 4% |
| Net revenue per valid click | $0.40 | $0.60 | $0.80 |
| Search revenue / 1,000 S | $2.40 | $9.00 | $20.80 |
| Variable delivery cost / 1,000 S | $6.50 | $6.50 | $6.50 |
| Search contribution / 1,000 S | -$4.10 | $2.50 | $14.30 |

At the working-case 50% coverage and 3% CTR, break-even net CPC is $6.50/(1,000×0.50×0.03) = $0.4333. If another 20% fee has not already been deducted, gross CPC must be at least $0.5417 under these assumptions. Do not apply the same deduction twice.

At 300,000 S/month, the working case gives $2,700 net search revenue, $1,950 variable search delivery cost and $750 search contribution before fixed costs/news. One user making 90 searches/month produces just $0.225 of search contribution in this case. Paid acquisition can therefore consume the margin quickly. Do not forecast retention or conversion without measured evidence.

New Tab/news sponsor revenue may help, but keep its inventory and costs separate. A $500 campaign is not additive revenue until its contracted service is delivered, and the same impression cannot be sold/credited twice. The modeled 8-topic shared-news schedule costs $14.40/month in provider requests only if the rights permit it; storage-license, hosting, image and media costs may be additional.

## Inventory policy
Search: start with one Sponsored unit on appropriate commercial searches; clean organic results regardless of ad fill.
New Tab: one restrained static sponsor. No fullscreen interruption, notifications or forced attention.
News: at most one sponsor after six organic cards and two in a finite session; count other sponsored content toward density.
Private, school/student, warning/security/payment/sensitive-help surfaces: no ads in this release. No ads injected into external publisher pages.
No network creatives that are blocked by Wingman's own content rules. Ads do not receive a bypass because they pay.

## Honest privacy promise
Proposed, subject to verification: “Wingman does not build advertising profiles from your browsing history or sell your search history. Ads are selected from your current search or the page you're using—not a profile of you.”

Separately disclose that cloud search sends the query to Brave; its reviewed standard API notice allows up to 90-day query retention. Do not claim that a proxy strips information inside the query itself. Where zero provider retention is essential, the relevant enterprise agreement is a launch dependency.

Before an ad is clicked, the strict first-party mode does not call merchants/third-party ad trackers. After a deliberate visit, the advertiser receives a normal website visit and may apply its own data practices. Wingman must not claim to control every external site's behavior. Affiliate programs are optional only after explicit app/browser permissions and an acceptable tracking review; do not depend on Amazon or any merchant automatically approving this distribution.

## Reports that preserve privacy
Report campaign/date/placement totals, views, valid clicks, spend, refunds and broad nonsensitive aggregate categories where adequately populated. Do not offer raw query reports, user journeys, demographics, unique reach, individual conversions or retained identifiers. Keep local frequency limits local. Short-lived security/event tokens are not durable advertising profiles but still require honest engineering and deletion.

Advertiser CRM/invoices and financial ledgers are business records, not a consumer browsing database. Keep them separate and access-controlled. No subscriptions refers to users; advertisers can purchase defined campaigns without creating a paid consumer product.

## What not to do
Do not rely on banner CPM alone to cover a $5/1,000-query search bill.
Do not equate “non-personalized advertising” with no cookies or identifiers.
Do not count partner application, sample creatives or prepaid cash as earned revenue.
Do not build an expensive auction/SSP before winning advertisers.
Do not assume caching is allowed because it reduces costs.
Do not make revenue the reason to weaken protection or secretly change organic recommendations.


## V2 optimization
Keep existing ad-density limits as defaults. Improve actual approved demand coverage, campaign pacing, net rate/yield, relevant ad selection and unnecessary provider-call prevention before increasing density. An optional second search unit is a disabled experiment, not an automatic revenue assumption. Static banner/card sizes are alternative renderings of approved first-party placements, not extra ad calls. Settle real valid events, keep guaranteed commitments, and aggregate only adequately populated nonsensitive campaign metrics. No raw-query/behavioral dataset or paid organic ranking is permitted.

The public rate guide distinguishes successful billed calls from failures. Keep conservative attempt reservations for safety while reporting confirmed and unknown charges separately; do not present every network error as a real invoice charge. The v2 launcher adds only a bounded two-request local connectivity test, not unlimited development spending.
