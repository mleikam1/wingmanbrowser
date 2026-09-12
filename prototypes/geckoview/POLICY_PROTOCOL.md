# Isolated GeckoView request-policy prototype

This extension belongs only to the isolated engine comparison. It is not installed in the production WebView adapter and is not an engine selection setting. The build script copies the reviewed root `assets/policy/consumer_protection.json` to the extension's `baseline.json`; a second checked-in copy is intentionally absent. The extension checks its immutable sequence-1 SHA-256 before parsing the six category sets, path rules and trackers. Signed hot updates are not implemented in this prototype; a production promotion would need the same native/Dart generation transaction as the consumer adapter.

The native app owns the lifecycle, permissions, storage and extension installation. The background extension owns synchronous request interception. It has no content scripts, externally connectable page API, remote scripts, or `nativeMessagingFromContent` permission. No request URL, search text, cookie or body is sent over native messaging. Diagnostic messages contain aggregate counts only.

## Readiness protocol

Extension ID: `wingman-policy@wingmanbrowser.test`. Native messaging app: `wingman_policy`. Protocol version: `1`.

1. The extension registers `onBeforeRequest` synchronously with `blocking` and `<all_urls>` before loading the baseline or connecting. Requests remain denied until both baseline validation and native configuration succeed. There is no tab-ID filter: background and service-worker requests may carry `tabId: -1`.
2. Native installs/ensures the bundled extension, validates the background sender identity/environment with no page session, and explicitly enables private-browsing support. It must verify the resulting metadata and the extension readiness acknowledgement before opening either a normal or private browser session.
3. Native sends `{type:"configure", protocol:1, edition:"consumer", revision:1, restrictions:{blockedDomains:[], blockedUrls:[], searchBlocked:false}}`. Revisions are positive, increasing integers within this extension process. Every configuration first closes the gate. Invalid edition, domains, URLs or replayed revisions keep it closed. A valid restriction snapshot replaces the previous snapshot atomically and cannot remove mandatory entries.
4. After validation the extension returns `{type:"ready", protocol:1, revision:1, sequence:1, sha256:"f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f", purpose:"consumer-policy"}`. Native must match every field to the expected generation/revision. A generic successful installation callback is insufficient.
5. Native sends `{type:"suspend", protocol:1}` on explicit owner handoff, cleanup or loss of the owning browser runtime. The extension denies requests immediately and replies `suspended`. Reopening requires a newer valid configuration and ready acknowledgement. An ordinary Android permission chooser pausing the Activity must not itself suspend the browser request gate.
6. Port disconnection closes the gate. Asset/configuration errors return fixed error codes, with no input values. `diagnostics` returns readiness and allowed/blocked/rewritten counts; it grants no permission.

The native side must separately quiesce existing sessions during policy/lifecycle transitions. A suspension message cannot undo an already transmitted request, erase storage, close a picker, or prove cleanup finished.

## Request behavior and limits

The extension runs domain/path and additional-deny checks on each callback, including a callback that follows a redirect. Known provider searches use the same strict-search fixtures as Flutter. Result-wrapper destinations undergo the ordinary policy again. A non-GET navigation that would require rewriting is denied, except a POST already on DuckDuckGo's strict HTTPS host; that provider host independently supplies strict adult filtering while preserving the POST body. Ordinary form POSTs are left to the engine. Known autocomplete requests and third-party tracker matches are denied.

Resource-only `ws:` and `wss:` handshakes are compared with the equivalent HTTP/HTTPS host and path for mandatory, additional and tracker rules. The original transport is preserved: this comparison never emits a protocol redirect, bypasses certificate validation, or relaxes Gecko's mixed-content policy. Top-level WebSocket navigation remains unsupported.

Host tests can invoke the second redirect callback and prove the policy would deny it. They cannot prove the engine emits it. The same distinction applies to service workers, private sessions, cache hits, WebSockets and renderer crash recovery. Runtime tests must record positive controls and whether the denied destination was actually contacted. The extension is not a page-text/image classifier and cannot fill the existing mixed-host and limited alcohol/drug/nicotine data gaps.

Run from the repository root:

```sh
node --test prototypes/geckoview/tests/policy.test.cjs
```

The September 12 latest run passed 155 tests: 142 current shared strict-search fixtures and thirteen policy/readiness tests, including WebSocket allow/deny boundaries. `work/browser-readiness/geckoview-policy-tests.log` is the host receipt. Do not count it as a native or physical-device result.

## Actual engine resource proof

The September 12 debug-only instrumentation run on owned Android emulator `emulator-5560` passed one test containing three phases through the actual adapter and stable GeckoView `155.0.20260903215306`: normal images, private images, and normal service-worker fetches. Each phase rendered the allowed control and reported errors for both the direct denied target and an allowed URL redirecting to that target. The loopback server counted **one allowed request, one permitted redirect response, zero direct denied-target requests, and zero redirected denied-target requests** in each phase. The worker phase also fetched its page and worker script once. Native startup acknowledged valid baseline, private permission and matching configuration before any page opened.

Receipts are `work/browser-readiness/geckoview-resource-probe-result.txt` and `geckoview-resource-probe-logcat.txt`. This is test-owned engine networking, not consumer UI or physical-device acceptance. Total instrumentation time was 202.87 seconds under host memory/startup pressure; it is not a browser performance measurement. Earlier failed runs are retained: private-permission enablement restarted the extension and prematurely flushed pending capabilities as unavailable, then an initial engine-generated `about:blank` callback stopped the requested page. Those adapter lifecycle defects were repaired without relaxing the request gate.

This establishes a concrete improvement over the reproduced WebView redirect bypass for these three cases. It does not establish private-worker coverage, every cache/redirect protocol, WebSocket execution, full site compatibility, stable production update transactions, or acknowledged private-data cleanup. The stable scoped cleanup API returns `void`; the prototype reports that acknowledgement is unavailable and does not erase normal-profile data as a substitute.

## Verified official sources

Current stable metadata was read from [Mozilla Maven](https://maven.mozilla.org/maven2/org/mozilla/geckoview/geckoview/maven-metadata.xml): `org.mozilla.geckoview:geckoview:155.0.20260903215306`, metadata updated `20260904135215`. The matching [POM](https://maven.mozilla.org/maven2/org/mozilla/geckoview/geckoview/155.0.20260903215306/geckoview-155.0.20260903215306.pom) records MPL-2.0 and source revision `5fdfd0092780e85643e2cddc0e1b590c8b9ef860`. This coordinate is independent of the newer mozilla-central Javadoc channel. [Mozilla's quickstart](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/consumer/geckoview-quick-start.html) specifies its Maven repository and Java 17 support.

[Mozilla's GeckoView extension guide](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/consumer/web-extensions.html) documents bundled extension installation and recommends avoiding content-script native messaging when unnecessary. [MDN webRequest](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest) documents blocking permissions, redirect lifecycle and startup listener registration. It also identifies exceptions for unobservable redirect targets or insufficient URL/host permissions. [onBeforeRequest](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/webRequest/onBeforeRequest) is the cancellation hook; `onBeforeRedirect` alone cannot cancel. Mozilla's [background-request test](https://searchfox.org/firefox-main/source/toolkit/components/extensions/test/mochitest/test_ext_webrequest_filter.html) includes service-worker requests without a normal tab ID. These references define the contract; the bounded actual-runtime evidence above is recorded separately.

Distribution must preserve relevant notices and make matching covered source available as required by [MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/FAQ/). Independent new app files do not automatically become MPL-covered, but modified covered files and third-party components retain their obligations. Bundling the engine makes Wingman responsible for tracking, testing and shipping its security updates. No Firefox branding, accounts, telemetry configuration or commercial service credentials are imported by this extension.
