# Brave setup and commercial inquiry
Reviewed September 25, 2026. Reconfirm prices and terms when creating the account.

## V2 account status
The owner has already obtained an API credential. Skip new-account creation; verify the existing plan and use LOCAL_KEY_SETUP.md. Use a replacement key for ongoing development and production. The historical steps below are reference only and do not authorize a second account or a new purchase. Remaining commercial/storage/privacy questions still need their applicable answers.

## Account steps (reference only)
1. Register at https://api-dashboard.search.brave.com/register with the business identity that will operate Wingman.
2. Select the Search plan at https://api-dashboard.search.brave.com/app/plans — not the Answers plan for this release. The reviewed public price is $5 per 1,000 requests with $5 monthly credit; the page describes prepaid credits. Plan-specific/enterprise charges may differ. All plans require payment information according to the API privacy notice.
3. Start with a small development balance; avoid enabling any offered automatic replenishment without an explicit ceiling. A proposed $25 application-side development cap is not a statement about Brave's minimum purchase or a blanket spending approval.
4. Create a server-side API key; separate development/production credentials when supported, under the same legitimate business account. This separation is for security, never to evade quotas.
5. Run Codex phase 01 so it creates the hidden-entry setup utility. Then enter the key locally using that utility. Do not paste the key into ChatGPT/Codex prompts, .dart files, public configuration, screenshots or Git. Production uses an owner-approved secret manager reference.
6. Approve a small, counted smoke-test allowance. Codex must test through its own durable budget controls, not curl the provider repeatedly outside accounting.
7. Supply an explicitly authorized Wingman-only project/domain before cloud deployment. Leave unrelated applications untouched.

## Contact routing
Brave publishes api-sales@brave.com for API sales and bizdev@brave.com for business inquiries. Its adsales@brave.com address is identified as for businesses purchasing advertising; opening an advertiser account there is not the same as receiving ads/revenue for Wingman.
Use API sales for product/storage/retention terms, with business development for a possible search-ad distribution partnership. These are inquiry routes, not confirmed offers.

## Copy-ready inquiry — do not send automatically
Subject: Wingman Browser — branded search/news API use and privacy-first ad partnership

Hello Brave team,

I'm building Wingman Browser, a free consumer browser whose search and news interfaces will be branded Wingman. We are evaluating Brave Search API as our organic web and news provider.

Wingman applies permanent content protections and does not build behavioral advertising profiles or sell browsing/search histories. Searches would pass through our server-side gateway without forwarding end-user IP addresses, cookies or device IDs. We would like to display clearly labeled contextual sponsored placements selected from the current nonsensitive search or content section, separate from organic ranking.

Please confirm the appropriate agreement and pricing for:

• A public Wingman-branded web search product, including Android/iOS and our web search interface, with independently sold contextual ads next to organic results.
• Common scheduled news queries and a shared, finite snapshot delivered to many readers. Please specify permitted cache/storage duration, CDN distribution, refresh rules, attribution, filtering/reranking and saved-link behavior.
• Publisher titles, excerpts and article-associated thumbnails. Which display/proxy/cache rights are included, and which require separate permission?
• Zero Data Retention for search queries, and the applicable data-processing/retention terms for this deployment.
• Volume pricing and any minimum commitments.
• Whether Brave offers an ad-syndication or revenue-sharing arrangement for third-party branded search products using its organic API. If so, please share eligibility, inventory/platform requirements, pricing/revenue share, payout/invalid-traffic terms, required data fields, and restricted-category controls. We do not assume the standard API includes advertising demand.

We can provide screenshots and accurate measured traffic once the prototype is ready. At this stage, we do not want to commit to unsupported traffic guarantees or permit behavioral tracking.

Thank you,
Matt Leikam
Wingman Browser

## Record the response
Do not treat a support acknowledgement as a signed modification to standard terms. Record approved uses, rights, dates, rates and the actual executed agreement when needed. Have the operating company review public distribution/advertising/privacy obligations with appropriate counsel before production. If shared-news or zero-retention rights are unavailable or too expensive, keep those capabilities gated and use only already-authorized sources; do not silently weaken Wingman's disclosures.
