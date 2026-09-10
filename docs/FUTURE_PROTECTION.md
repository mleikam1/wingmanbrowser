# Future protection beyond the Wingman browser

Phase 2 Guard controls navigation inside Wingman's native browser. The web companion can apply local decisions before it hands a link to its host browser, but cannot control subsequent navigation in Safari, Chrome or other apps. No VPN, device-management profile, restricted entitlement request, extension or network-wide filter was created.

## Device-wide platform options

| Platform approach | Potential fit | Important boundary |
| --- | --- | --- |
| Android `VpnService` | A separately designed local packet/DNS filtering product | Requires the OS user's VPN authorization; only one active VPN per user/profile. Must coexist with user VPN expectations, networking, battery and store policy. Encrypted traffic does not reveal full HTTPS paths to a simple local packet filter. |
| Android managed-device controls | Organization-managed deployments | Device-owner/profile-owner eligibility and management enrollment are distinct products, not an invisible consumer-browser upgrade. |
| Apple Family Controls / Screen Time | Authorized app/web-domain shields and scheduling | Distribution requires Apple's approval for relevant app and Screen Time extension identifiers. User/guardian authorization and the API's privacy boundaries must be respected. |
| Apple Network Extension content filter | Supported supervised/managed or eligible child Screen Time configurations | Deployment restrictions differ by provider, OS and authorization. Individual self-control authorization does not automatically grant every network-filter capability. |
| Apple iOS/macOS 26 URL Filter | Future privacy-preserving system URL decisions | A newer separate architecture using Bloom filters, PIR, Privacy Pass and OHTTP. Managed and unmanaged device support exists, but distribution use of Apple's relay requires application/configuration and real-device validation. |

Android documents the prepared-VPN consent step and single-active-service constraint. A future local filtering design needs explicit traffic forwarding, failure, DNS, QUIC, IPv6 and encrypted-DNS behavior. It must not quietly route browsing through Wingman servers or be described as a functioning VPN before those properties are implemented. [Android VPN guide](https://developer.android.com/develop/connectivity/vpn)

Apple's Family Controls distribution approval is an external requirement; no eligibility or approved entitlement is asserted here. [Requesting Family Controls](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

Apple's deployment table distinguishes content filters, DNS proxies, packet tunnels and the newer URL filters. For example, iOS content-filter support through Screen Time has child-device authorization constraints, while ordinary DNS proxy deployment has supervised/managed restrictions. Do not generalize one provider's development behavior to a distributable consumer product. [Network Extension deployment](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)

Apple specifically cautions against using packet tunnels as a generic content-filter substitute or intercepting all system DNS traffic through the wrong provider type. The iOS/macOS 26 URL Filter architecture is especially relevant to Wingman's mission because the app does not execute in the URL filtering path or receive URL traffic. It is future work requiring separate infrastructure, Apple relay configuration and device tests, not a capability shipped by this browser build. [Expected packet-tunnel use cases](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [Apple URL Filter presentation](https://developer.apple.com/videos/play/wwdc2025/234/)

Any device-wide proposal must first establish its supported traffic scope, bypass behavior, authorized user controls, collision with other VPN/protection tools, store rules, entitlements and privacy model. Guard inside Wingman remains useful if that separate product never ships.

## Desktop extension architecture

A future Chrome/Edge/Firefox extension can share the normalized domain policy, signed-pack verifier, safe-search rules and neutral blocked-page language, with an adapter for each browser's declarative request engine. Extension-local preferences and counters remain separate from advertising, and Incognito/Private support requires explicit user/browser permission handling. Do not sync history or filters through browser sync by default.

Chrome Manifest V3's `declarativeNetRequest` lets the browser evaluate rules without delivering request contents to extension code. Prefer static rules for shipped data, dynamic rules for verified updates/custom settings, and session rules for temporary exceptions. Test the actual installed browser's quotas and rule precedence; do not publish millions of rules or assume every rule format maps one-to-one. Redirecting to an owned blocked page may need additional host permissions and careful preservation of the attempted destination in local memory. [Chrome declarative API](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest)

Firefox also provides declarative rules, while retaining blocking `webRequest` capabilities under its permission model. Prefer declarative rules where adequate; any imperative adapter should have bounded local policy and avoid URL logging. Request the minimum necessary permissions, explain why all-site filtering needs broad scope, and leave unrelated cookies/history/native-messaging permissions absent. Edge needs its own packaging/store review rather than an assumption of Chrome store approval. [Mozilla request interception](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Intercept_HTTP_requests), [Firefox permissions](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/permissions)

No extension is implemented in Phase 2. Acceptance for a future extension must include redirects, subframes, new tabs, target-blank links, persisted and session exceptions, browser restart, private windows, extension disable/uninstall, and accurate distinction between extension protection and the Wingman web companion.
