# Sources and scope
Official sources reviewed September 25, 2026. Documentation, prices and agreements may change; re-read before implementation and contracting. These references establish product capabilities and published rules, not account approval or legal advice. All financial scenarios, engineering targets, launch gates and package rates in this pack are proposed assumptions.

## Brave
- Search plan/pricing: https://api-dashboard.search.brave.com/app/plans
- API overview and storage/copyright FAQ: https://brave.com/search/api/
- Registration: https://api-dashboard.search.brave.com/register
- API terms (page states September 1, 2026 update): https://api-dashboard.search.brave.com/terms-of-service
- API privacy (page states August 25, 2026 update): https://api-dashboard.search.brave.com/privacy-policy
- Web search guide: https://api-dashboard.search.brave.com/documentation/services/web-search
- Web API reference: https://api-dashboard.search.brave.com/api-reference/web/search/get
- News guide: https://api-dashboard.search.brave.com/documentation/services/news-search
- News API reference: https://api-dashboard.search.brave.com/api-reference/news/news_search/get
- Brave Search Ads advertiser offering and published API/business contacts: https://brave.com/brave-ads/search/

The public Search Ads page is advertiser-facing. No publicly documented turnkey third-party Wingman ad-demand/revenue-share entitlement was verified. Obtain a separate agreement rather than treating the organic API key as that entitlement.

## Privacy, disclosure and infrastructure
- FTC native-ad disclosure: https://www.ftc.gov/business-guidance/resources/native-advertising-guide-businesses
- FTC endorsement/affiliate disclosure: https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking
- Google explanation that non-personalized ads can still use identifiers: https://support.google.com/adsense/answer/9007336?hl=en
- Google AFS introduction and application review: https://support.google.com/adsense/answer/9879?hl=en
- Google Cloud budgets and alerts: https://docs.cloud.google.com/billing/docs/how-to/budgets
- Google Secret Manager practices: https://docs.cloud.google.com/secret-manager/docs/best-practices

## Repository inspected through the connected GitHub tool
- https://github.com/mleikam1/wingmanbrowser/blob/main/README.md
- https://github.com/mleikam1/wingmanbrowser/blob/main/docs/CURRENTS_INTEGRATION.md
- https://github.com/mleikam1/wingmanbrowser/blob/main/backend/wingman_content/provider.py

This was a targeted architecture/integration review, not a full security audit or live build test. No repository changes, live API requests using the user's credentials, account signups, outreach, cloud deployments, advertiser charges or production revenue verification were performed in preparing this pack.


## V2 verification — September 26, 2026
Rechecked the Brave overview, quickstart, authentication, Web and News guides/references, rate limiting, plans, terms, privacy and Search Ads page. New reference pointers:
- https://api-dashboard.search.brave.com/documentation
- https://api-dashboard.search.brave.com/documentation/quickstart
- https://api-dashboard.search.brave.com/documentation/guides/authentication
- https://api-dashboard.search.brave.com/documentation/guides/rate-limiting
- https://ads-help.brave.com/campaign-performance/API/

The preceding no-live-request statement describes v1 only. For v2, two transport attempts to the authorized Web Search endpoint failed without an API response. No successful authentication, balance check, news response or charge was verified. The credential and response content were not saved in this package. See CONNECTIVITY_CHECK.json. No application-code changes, deployment, account purchase, outreach or advertiser charge was made here. Current local repository inspection remains Codex's first step. Non-Brave sources above are retained v1 references and should be revalidated if relied on during implementation.
