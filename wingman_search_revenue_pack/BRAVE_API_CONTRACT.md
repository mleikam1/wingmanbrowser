# Brave integration contract — v2
Reviewed September 26, 2026. Recheck the cited official references during implementation; account-specific entitlements remain unverified.

## Official API mapping
| Purpose | Full request URL | Result array |
|---|---|---|
| Human web results | `https://api.search.brave.com/res/v1/web/search` | `web.results` |
| News search | `https://api.search.brave.com/res/v1/news/search` | `results` |

Authenticate through the `X-Subscription-Token` header. Send `Accept: application/json`. Keep the token exclusively in the server-side client. The current quickstart emphasizes LLM Context; use the Web Search guide for this product instead.

References: [Authentication](https://api-dashboard.search.brave.com/documentation/guides/authentication), [Web reference](https://api-dashboard.search.brave.com/api-reference/web/search/get), [News reference](https://api-dashboard.search.brave.com/api-reference/news/news_search/get), [Quickstart](https://api-dashboard.search.brave.com/documentation/quickstart).

## Wingman request policy
These defaults are Wingman implementation choices, not a claim that every listed parameter is required by Brave.

Web: `q`, selected `country/search_lang/ui_lang`, `safesearch=strict`, `count=20`, `offset=0`, `result_filter=web`, `text_decorations=false`. Keep `extra_snippets`, `summary` and rich callbacks off unless an independently reviewed feature needs them.

News: `q`, selected `country/search_lang/ui_lang`, `safesearch=strict`, `count=20`, `offset=0`; add a reviewed freshness window for an intentional news feature. Do not send web-only parameters to news. Shared-feed count may be tuned within the documented maximum only after appropriate rights and cost review.

Both references limit queries to 400 characters and 50 words. Web count is at most 20; news count at most 50. Both use page offsets 0–9, not item offsets. Web exposes `query.more_results_available`; do not require that field in News, whose documented schema differs. For News, use documented metadata when present, otherwise conservative count-based UX and explicit user activation; never perform a hidden next-page probe. Validate supported locale values instead of accepting arbitrary strings. Sources: the Web and News references above.

Do not trim or rewrite a user's query silently merely to fit the limit. Return a useful validation message. Do not pass through caller-controlled headers, URLs, location fields or safety overrides. Avoid forwarding precise location, consumer IP, cookies or client identifiers. A constant service identity is not a per-user identifier. Reject redirects for credential-bearing provider calls. Use bounded decoding, schemas and safe text rendering even when decoration is disabled.

Provider flags or a successful strict request do not certify every Wingman content rule. Apply Wingman policy independently before requests, before rendering and during supported navigation. Reassess altered/spellchecked queries for ad eligibility; uncertain or sensitive intent means no ad, not a bypass.

## Cost and failure accounting
Brave lists Search at $5 per 1,000 requests with monthly credits. Do not assume the owner's remaining balance or commercial terms from that public rate. The rate guide says successful requests are billed; an internal conservative reservation is NOT a confirmed invoice charge. Track attempts, confirmed successful responses, unknown outcomes and reconciled charges separately. Two successful ordinary Search calls would be $0.01 at that list rate before credits or account adjustments. Sources: [Plans](https://api-dashboard.search.brave.com/app/plans), [Rate limiting](https://api-dashboard.search.brave.com/documentation/guides/rate-limiting).

Honor all returned limit windows and reset/backoff instructions. Do not hardcode the published headline QPS as proof of this account's allowance. Disable automatic smoke-test retries. Do not log HTTP exception objects that include query-bearing URLs. Report sanitized error classes and statuses without request or credential content. An exhausted local attempt cap stays exhausted across reruns/key rotation; replacing a credential does not create a new budget.

## Commercial boundary
Wingman buys result data and separately earns ad revenue from actual approved campaigns. Brave's [Search Ads page](https://brave.com/brave-ads/search/) sells advertising on Brave Search. Its [advertiser reporting API](https://ads-help.brave.com/campaign-performance/API/) is not proof of a publisher demand feed. Do not conflate these services or reuse their credentials interchangeably.

Preserve applicable rights gates and disclosures from the master. Read [Terms](https://api-dashboard.search.brave.com/terms-of-service) and [Privacy](https://api-dashboard.search.brave.com/privacy-policy). Neither a working token nor this document establishes custom storage rights, Zero Data Retention, publisher-image rights or an advertising partnership.
