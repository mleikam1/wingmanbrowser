@testable import Runner
import Network
import Flutter
import CryptoKit
import UIKit
import WebKit
import XCTest

final class RunnerTests: XCTestCase {
  private func consumerPolicy() throws -> ConsumerNativePolicy {
    let app = try XCTUnwrap(Bundle(path: Bundle.main.bundlePath + "/Frameworks/App.framework"))
    let asset = try XCTUnwrap(app.path(forResource: "consumer_protection", ofType: "json", inDirectory: "flutter_assets/assets/policy"))
    return ConsumerNativePolicy(path: asset, expectedDigest: ProtectedWebBridge.protectionSHA256)
  }

  func testConsumerNativePolicyUnknownStrictAndMixedPaths() throws {
    let policy = try consumerPolicy()
    XCTAssertTrue(policy.valid)
    XCTAssertGreaterThan(policy.domainCount, 300000)
    for raw in ["https://www.weather.gov/", "https://www.nasa.gov/", "https://www.espn.com/nba/", "https://www.walmart.com/shop/electronics", "http://127.0.0.1:8123/fixture"] {
      XCTAssertNotNil(policy.check(raw).url, raw)
    }
    for raw in ["https://sexual-explicit.protection.test/", "https://gambling.protection.test/", "https://security-threat.protection.test/", "https://www.espn.com/espn/betting/", "https://mixed.protection.test/promotion/alcohol/", "https://mixed.protection.test/promotion//alcohol", "https://mixed.protection.test//promotion/alcohol", "https://mixed.protection.test/promotion/x/../alcohol", "https://mixed.protection.test/promotion/%61lcohol", "file:///etc/passwd", "https://user:pass@example.com/"] {
      XCTAssertNil(policy.check(raw).url, raw)
    }
    XCTAssertEqual(policy.check("https://duckduckgo.com/?q=space&kp=-2").url?.host, "safe.duckduckgo.com")
    XCTAssertEqual(policy.check("https://google.com/search?q=space").url?.host, "safe.duckduckgo.com")
    XCTAssertNil(policy.check("https://safe.duckduckgo.com/?q=!g+space").url)
    XCTAssertNotNil(policy.check("https://safe.duckduckgo.com/?q=Hello!").url)
    XCTAssertEqual(strictSearchURL("C++!"), "https://safe.duckduckgo.com/?q=C%2B%2B%21&kp=1&kac=-1")
    XCTAssertNil(policy.check("https://safe.duckduckgo.com/l/?uddg=https%3A%2F%2Fgambling.protection.test%2F").url)
    let corrupt = ConsumerNativePolicy(path: "/missing", expectedDigest: "0")
    XCTAssertFalse(corrupt.valid)
    XCTAssertNil(corrupt.check("https://www.nasa.gov/").url)
  }

  func testDialogReplyCompletesOnceAcrossDismissalAndLateAction() {
    var replies = [Bool]()
    let reply = ConsumerReply<Bool> { replies.append($0) }
    reply.resolve(false) // Renderer release cancels a pending dialog.
    reply.resolve(true) // A late UIKit action must not call WebKit again.
    XCTAssertEqual(replies, [false])
  }

  func testExportPickerCannotResolvePendingUploadOrReplayAfterCancellation() {
    let upload = NSObject(), oldExport = NSObject()
    var replies = [String?]()
    let reply = ConsumerOwnedReply<String?>(owner: upload) { replies.append($0) }
    reply.resolve(from: oldExport, value: "export destination must not become an upload")
    XCTAssertTrue(replies.isEmpty)
    reply.resolve(from: upload, value: "selected synthetic upload")
    reply.resolve(from: upload, value: "late duplicate")
    XCTAssertEqual(replies, ["selected synthetic upload"])

    let pending = ConsumerOwnedReply<String?>(owner: upload) { replies.append($0) }
    pending.cancel(nil) // Closing the renderer consumes only this request.
    pending.resolve(from: upload, value: "late result after tab close")
    XCTAssertEqual(replies.count, 2)
    XCTAssertNil(replies.last!)
  }

  func testPopupLeaseRejectsChangedDocumentProfileRestrictionAndExpiry() {
    let renderer = NSObject(), other = NSObject(), now = Date()
    let lease = ConsumerWindowOwnerSnapshot(renderer: ObjectIdentifier(renderer), generation: 4,
      origin: "https://fixture.protection.test:443", restrictionVersion: 2, expiresAt: now.addingTimeInterval(10))
    XCTAssertTrue(lease.matches(renderer: renderer, generation: 4, origin: lease.origin, restrictionVersion: 2, now: now))
    XCTAssertFalse(lease.matches(renderer: other, generation: 4, origin: lease.origin, restrictionVersion: 2, now: now))
    XCTAssertFalse(lease.matches(renderer: nil, generation: 4, origin: lease.origin, restrictionVersion: 2, now: now))
    XCTAssertFalse(lease.matches(renderer: renderer, generation: 5, origin: lease.origin, restrictionVersion: 2, now: now))
    XCTAssertFalse(lease.matches(renderer: renderer, generation: 4, origin: "https://changed.protection.test:443", restrictionVersion: 2, now: now))
    XCTAssertFalse(lease.matches(renderer: renderer, generation: 4, origin: lease.origin, restrictionVersion: 3, now: now))
    XCTAssertFalse(lease.matches(renderer: renderer, generation: 4, origin: lease.origin, restrictionVersion: 2, now: now.addingTimeInterval(10)))
  }

  @MainActor
  func testNativePopupAdoptionRetainsPostOpenerAndPrivateProfile() throws {
    let ready = expectation(description: "Popup fixture server starts")
    let server = try ContentRuleFixtureServer(png: Data(), ready: ready)
    defer { server.stop() }
    wait(for: [ready], timeout: 5)
    let port = try XCTUnwrap(server.port)
    let origin = "http://127.0.0.1:\(port)"
    let compiled = expectation(description: "Popup fixture resource rule compiles")
    var rule: WKContentRuleList?
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "wingman-popup-test-" + UUID().uuidString,
      encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\"^https://blocked.invalid/\"},\"action\":{\"type\":\"block\"}}]") { value, error in
      XCTAssertNil(error); rule = value; compiled.fulfill()
    }
    wait(for: [compiled], timeout: 10)
    let policy = try consumerPolicy(), compiledRule = try XCTUnwrap(rule)
    for privateMode in [false, true] {
      let messenger = PopupTestMessenger()
      let bridge = ProtectedWebBridge(testPolicy: policy, rules: [compiledRule], messenger: messenger)
      defer { bridge.closeAll() }
      let args: [String: Any] = ["tabId": "parent", "private": privateMode, "edition": "consumer"]
      let parent = bridge.create(withFrame: CGRect(x: 0, y: 0, width: 430, height: 700), viewIdentifier: 710, arguments: args)
      messenger.invoke("open", ["viewId": 710, "requestId": 1, "url": origin + "/popup-parent"])
      let parentWeb = try XCTUnwrap(parent.view().subviews.compactMap { $0 as? WKWebView }.first)
      let window = UIWindow(frame: parent.view().frame); let controller = UIViewController()
      window.rootViewController = controller; controller.view.addSubview(parent.view()); window.isHidden = false
      defer { window.isHidden = true }
      waitForJavaScript(parentWeb, "document.title === 'Popup parent'")
      var childViews: [FlutterPlatformView] = []
      var nextId: Int64 = 711
      messenger.onEvent = { call in
        guard call.method == "newWindowRequested", let event = call.arguments as? [String: Any], let token = event["windowToken"] as? String else { return }
        // Match the asynchronous Flutter factory + adoption round trip.
        DispatchQueue.main.async {
          let id = nextId; nextId += 1
          let child = bridge.create(withFrame: parent.view().frame, viewIdentifier: id,
            arguments: ["tabId": "child-\(id)", "private": privateMode, "edition": "consumer", "windowToken": token])
          childViews.append(child); controller.view.addSubview(child.view())
          messenger.invoke("adoptWindow", ["viewId": id, "requestId": 1, "windowToken": token])
        }
      }
      parentWeb.evaluateJavaScript("document.getElementById('get-child').click()", completionHandler: nil)
      waitForJavaScript(parentWeb, "document.getElementById('result').textContent === 'GET opener retained'")
      XCTAssertEqual(childViews.count, 1)
      let getChild = try XCTUnwrap(childViews.first?.view().subviews.compactMap { $0 as? WKWebView }.first)
      XCTAssertTrue(getChild.configuration.websiteDataStore === parentWeb.configuration.websiteDataStore)
      XCTAssertEqual(getChild.configuration.websiteDataStore.isPersistent, !privateMode)
      parentWeb.evaluateJavaScript("document.getElementById('post-child').click()", completionHandler: nil)
      waitForJavaScript(parentWeb, "document.getElementById('result').textContent === 'POST opener retained'")
      XCTAssertEqual(childViews.count, 2)
      XCTAssertFalse(messenger.errors.contains { $0 != nil })
      let postChild = try XCTUnwrap(childViews.last?.view().subviews.compactMap { $0 as? WKWebView }.first)
      waitForJavaScript(postChild, "document.body.textContent.includes('marker=synthetic-post-body')")
      let closed = expectation(description: "Script child close event")
      messenger.onEvent = { call in if call.method == "closeRequested" { closed.fulfill() } }
      postChild.evaluateJavaScript("window.close()", completionHandler: nil)
      wait(for: [closed], timeout: 5)
      XCTAssertTrue(childViews.last?.view().subviews.isEmpty == true)
    }
    XCTAssertEqual(server.counts["/popup-post"], 2, "Each normal/private popup sends its original POST once")
  }

  @MainActor
  private func waitForJavaScript(_ web: WKWebView, _ predicate: String, file: StaticString = #filePath, line: UInt = #line) {
    let reached = expectation(description: "JavaScript fixture condition")
    let deadline = Date().addingTimeInterval(7)
    func check() {
      web.evaluateJavaScript(predicate) { value, error in
        if value as? Bool == true { reached.fulfill(); return }
        if Date() >= deadline { XCTFail("Fixture condition did not become true: \(predicate), error: \(String(describing: error))", file: file, line: line); reached.fulfill(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
      }
    }
    check(); wait(for: [reached], timeout: 9)
  }

  @MainActor
  func testHiddenWebActivityEndsCaptureAndReturnNeverRestartsCapture() {
    let web = ActivityRecordingWebView(frame: .zero, configuration: consumerWebConfiguration(privateMode: true, rules: []))
    consumerSetWebActivity(web, allowed: false)
    XCTAssertEqual(web.playbackSuspension, [true])
    XCTAssertEqual(web.cameraChanges, [.none])
    XCTAssertEqual(web.microphoneChanges, [.none])
    XCTAssertEqual(web.closedPresentations, 1)
    consumerSetWebActivity(web, allowed: true)
    XCTAssertEqual(web.playbackSuspension, [true, false])
    XCTAssertEqual(web.cameraChanges, [.none], "Returning must not resume an old capture grant")
    XCTAssertEqual(web.microphoneChanges, [.none])
  }

  func testExpectedPolicyCancellationNeverSuppressesCertificateOrNetworkErrors() {
    XCTAssertTrue(consumerExpectedNavigationCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), policyCancellationExpected: false))
    let interrupted = NSError(domain: "WebKitErrorDomain", code: 102)
    XCTAssertTrue(consumerExpectedNavigationCancellation(interrupted, policyCancellationExpected: true))
    XCTAssertFalse(consumerExpectedNavigationCancellation(interrupted, policyCancellationExpected: false))
    XCTAssertFalse(consumerExpectedNavigationCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted), policyCancellationExpected: true))
    XCTAssertFalse(consumerExpectedNavigationCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), policyCancellationExpected: true))
  }

  func testConsumerSameCurrentRestorePreservesRollbackPredecessor() {
    let previous: [String: Any] = ["sequence": 2, "sha256": "previous-digest"]
    let restored = consumerActivationReceipt(currentSequence: 3, currentDigest: "active-digest", previous: previous,
      sequence: 3, digest: "active-digest", highWater: 5)
    XCTAssertEqual(restored["highest"] as? Int, 5)
    XCTAssertEqual((restored["previous"] as? [String: Any])?["sequence"] as? Int, 2)
    XCTAssertEqual((restored["previous"] as? [String: Any])?["sha256"] as? String, "previous-digest")
    let upgraded = consumerActivationReceipt(currentSequence: 3, currentDigest: "active-digest", previous: previous,
      sequence: 6, digest: "new-digest", highWater: 5)
    XCTAssertEqual(upgraded["highest"] as? Int, 6)
    XCTAssertEqual((upgraded["previous"] as? [String: Any])?["sequence"] as? Int, 3)
  }

  func testConsumerSignedUpdateAuthenticityAndMetadata() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let keys = ["test-ephemeral": privateKey.publicKey.rawRepresentation.base64EncodedString()]
    let generated = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
    let categories = Dictionary(uniqueKeysWithValues: ["sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat"].map { ($0, [$0 + ".protection.test"]) })
    let body: [String: Any] = ["schemaVersion": 1, "sequence": 2, "version": "test.2", "generatedAt": generated,
      "categories": categories, "trackers": [String](), "pathRules": [[String: String]]()]
    let bytes = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    var meta: [String: Any] = ["purpose": "wingman-consumer-protection-v1", "schemaVersion": 1,
      "sequence": 2, "version": "test.2", "generatedAt": generated, "minimumAppVersion": "0.10.0",
      "filename": "consumer-2.json", "sha256": digest, "bytes": bytes.count, "license": "Test-only synthetic data"]
    func envelope(_ metadata: [String: Any], corruptSignature: Bool = false) throws -> Data {
      let payload = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
      var signature = try privateKey.signature(for: payload)
      if corruptSignature { signature[0] ^= 0xff }
      return try JSONSerialization.data(withJSONObject: ["keyId": "test-ephemeral", "payload": payload.base64EncodedString(), "signature": signature.base64EncodedString()])
    }
    let signed = try envelope(meta)
    let verified = try ConsumerNativeUpdate(envelope: signed, data: bytes, keys: keys)
    XCTAssertEqual(verified.sequence, 2)
    XCTAssertFalse(verified.prepared, "Signature verification alone cannot activate uncompiled rules")
    XCTAssertNotNil(verified.policy.check("https://www.nasa.gov/").url)
    XCTAssertNil(verified.policy.check("https://gambling.protection.test/").url)
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: signed, data: bytes, keys: [:]))
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: envelope(meta, corruptSignature: true), data: bytes, keys: keys))
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: signed, data: bytes + Data([32]), keys: keys))
    meta["sequence"] = 3
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: envelope(meta), data: bytes, keys: keys))
    meta["sequence"] = 2; meta["minimumAppVersion"] = "999.0.0"
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: envelope(meta), data: bytes, keys: keys))
    meta["minimumAppVersion"] = "0.10.0"; meta["generatedAt"] = "2099-01-01T00:00:00Z"
    XCTAssertThrowsError(try ConsumerNativeUpdate(envelope: envelope(meta), data: bytes, keys: keys))
  }

  @MainActor
  func testConsumerNativeRuleCompilerBlocksSyntheticAndAllowsNeutralResources() throws {
    let policy = try consumerPolicy()
    // Production compiler is exercised; fixed synthetic rules are included in
    // the signed baseline. We don't fetch prohibited sites to test their rules.
    let groups = policy.contentRuleGroups()
    XCTAssertFalse(groups.isEmpty)
    XCTAssertGreaterThan(groups.count, 10)
    XCTAssertFalse(groups.joined().contains("block-cookies"))
    XCTAssertFalse(groups.joined().contains("ignore-previous-rules"))
    let complete = expectation(description: "Consumer rule chunk compiles")
    let identifier = "wingman-consumer-xctest-" + UUID().uuidString
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: try XCTUnwrap(groups.first)) { list, error in
      XCTAssertNil(error)
      XCTAssertNotNil(list)
      WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in complete.fulfill() }
    }
    wait(for: [complete], timeout: 120)
  }

  @MainActor
  func testConsumerConfigurationPreservesNormalCookiesSeparatesPrivateAndEnablesJavaScript() throws {
    let normal = consumerWebConfiguration(privateMode: false, rules: [])
    let privateSession = consumerWebConfiguration(privateMode: true, rules: [])
    XCTAssertTrue(normal.websiteDataStore.isPersistent)
    XCTAssertFalse(privateSession.websiteDataStore.isPersistent)
    XCTAssertTrue(normal.defaultWebpagePreferences.allowsContentJavaScript)
    XCTAssertFalse(normal.preferences.javaScriptCanOpenWindowsAutomatically)
    XCTAssertTrue(normal.preferences.isFraudulentWebsiteWarningEnabled)
    if #available(iOS 15.4, *) { XCTAssertTrue(normal.preferences.isElementFullscreenEnabled) }
    let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "session.protection.test", .path: "/", .name: "wingman_native_fixture", .value: "synthetic", .expires: Date().addingTimeInterval(60)]))
    let stored = expectation(description: "Normal fixture cookie stored")
    normal.websiteDataStore.httpCookieStore.setCookie(cookie) { stored.fulfill() }
    wait(for: [stored], timeout: 10)
    let continuity = expectation(description: "New normal configuration shares cookies")
    consumerWebConfiguration(privateMode: false, rules: []).websiteDataStore.httpCookieStore.getAllCookies { cookies in
      XCTAssertTrue(cookies.contains(where: { $0.name == cookie.name && $0.domain == cookie.domain })); continuity.fulfill()
    }
    let isolated = expectation(description: "Private session has no normal fixture cookie")
    privateSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
      XCTAssertFalse(cookies.contains(where: { $0.name == cookie.name && $0.domain == cookie.domain })); isolated.fulfill()
    }
    wait(for: [continuity, isolated], timeout: 10)
    let cleaned = expectation(description: "Only synthetic test cookie removed")
    normal.websiteDataStore.httpCookieStore.delete(cookie) { cleaned.fulfill() }
    wait(for: [cleaned], timeout: 10)
  }

  @MainActor
  func testConsumerPathResourceRulesRejectAlternateSpellingsWithPositiveControl() throws {
    let ready = expectation(description: "Test-owned resource server starts")
    let imageFormat = UIGraphicsImageRendererFormat(); imageFormat.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: imageFormat).image { context in
      UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    let server = try ContentRuleFixtureServer(png: XCTUnwrap(image.pngData()), ready: ready)
    defer { server.stop() }
    wait(for: [ready], timeout: 5)
    let origin = "http://127.0.0.1:\(try XCTUnwrap(server.port))"
    // Test-owned policy data exercises the production parser and rule builder;
    // neither this data nor an override entry point exists in the app target.
    let categories = Dictionary(uniqueKeysWithValues: ["sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat"].map { ($0, [$0 + ".protection.test"]) })
    let bytes = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sequence": 1, "categories": categories,
      "pathRules": [["host": "127.0.0.1", "pathPrefix": "/promotion/alcohol", "category": "alcohol-promotion"]], "trackers": [String]()])
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let policy = ConsumerNativePolicy(data: bytes, expectedDigest: digest)
    XCTAssertTrue(policy.valid)
    let forbidden = ["/promotion/alcohol", "/promotion//alcohol", "//promotion/alcohol", "/promotion/%61lcohol", "/promotion/%41lcohol", "/promotion%2falcohol", "/promotion/x/../alcohol", "/promotion/%2e/alcohol"]
    for path in forbidden { XCTAssertNil(policy.check(origin + path).url, path) }
    let permitted = [origin + "/allowed.png", origin + "/consumer-allowed/space%20name.png", origin + "/consumer-allowed/%E2%98%83.png", origin + "/allowed.png?label=%61", origin + "/promotion/alcohol-reporting", origin.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "/consumer-allowed/%61rticle.png"]
    for url in permitted { XCTAssertNotNil(policy.check(url).url, url) }
    let ambiguousNeutral = policy.check(origin + "/consumer-allowed/%61rticle.png")
    XCTAssertNil(ambiguousNeutral.url)
    XCTAssertTrue(ambiguousNeutral.reason.contains("standard address"))
    let compiled = expectation(description: "Current supplemental resource rules compile")
    let identifier = "wingman-xctest-consumer-paths-" + UUID().uuidString
    defer { WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in } }
    var ruleList: WKContentRuleList?
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: try XCTUnwrap(policy.contentRuleGroups().last)) { list, error in
      XCTAssertNil(error); ruleList = list; compiled.fulfill()
    }
    wait(for: [compiled], timeout: 15)
    let configuration = consumerWebConfiguration(privateMode: true, rules: [try XCTUnwrap(ruleList)])
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    let loaded = expectation(description: "Resource fixture finishes")
    let delegate = ContentRuleNavigationObserver(loaded: loaded); web.navigationDelegate = delegate
    defer { web.stopLoading(); web.navigationDelegate = nil }
    let images = forbidden.enumerated().map { "<img id='blocked\($0.offset)' src='\(origin)\($0.element)'>" }.joined()
    let allowedImages = permitted.enumerated().map { "<img id='allowed\($0.offset)' src='\($0.element)'>" }.joined()
    web.loadHTMLString("<!doctype html><title>Owned path fixture</title>" + allowedImages + images, baseURL: URL(string: origin))
    wait(for: [loaded], timeout: 20)
    XCTAssertNil(delegate.error)
    let inspected = expectation(description: "Permitted image decodes; blocked spellings do not reach the server")
    web.evaluateJavaScript("Array.from(document.images).map(i=>i.naturalWidth)") { value, error in
      XCTAssertNil(error); XCTAssertEqual(value as? [Int], Array(repeating: 4, count: permitted.count) + Array(repeating: 0, count: forbidden.count)); inspected.fulfill()
    }
    wait(for: [inspected], timeout: 5)
    XCTAssertEqual(server.counts["/allowed.png"], 2)
    XCTAssertEqual(server.counts.values.reduce(0, +), permitted.count, "A blocked spelling reached the owned server: \(server.counts)")
  }

  /// This fixture uses the actual production rule builder with test-owned
  /// loopback URLs. There is no production manifest override or app-channel
  /// loader for localhost, arbitrary HTML or caller-supplied JavaScript.
  @MainActor
  func testWebKitBlocksUnreviewedResourcesAndResourceRedirects() throws {
    let ready = expectation(description: "Owned loopback server starts")
    let imageFormat = UIGraphicsImageRendererFormat()
    imageFormat.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: imageFormat).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
    let server = try ContentRuleFixtureServer(png: XCTUnwrap(image.pngData()), ready: ready)
    defer { server.stop() }
    wait(for: [ready], timeout: 5)
    let port = try XCTUnwrap(server.port, server.startError ?? "No listener port")
    let origin = "http://127.0.0.1:\(port)"
    let document = origin + "/document"
    let rules = try XCTUnwrap(protectedContentRuleJSON(
      documents: [document],
      resources: [
        origin + "/allowed.png": "image",
        origin + "/redirect.png": "image",
        origin + "/allowed.css?modules=one%7Ctwo%2Cthree&only=styles": "styleSheet",
      ],
      privacyDomains: []
    ))
    let identifier = "wingman-xctest-owned-rules-\(UUID().uuidString)"
    defer { WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in } }
    let compiled = expectation(description: "Production rule JSON compiles in real WebKit")
    var list: WKContentRuleList?
    var compileError: Error?
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: identifier,
      encodedContentRuleList: rules
    ) { result, error in
      list = result
      compileError = error
      compiled.fulfill()
    }
    wait(for: [compiled], timeout: 10)
    XCTAssertNil(compileError)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.userContentController.add(try XCTUnwrap(list))
    let loaded = expectation(description: "Owned HTML document finishes")
    let delegate = ContentRuleNavigationObserver(loaded: loaded)
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    web.navigationDelegate = delegate
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      web.removeFromSuperview()
    }
    web.load(URLRequest(url: try XCTUnwrap(URL(string: document))))
    wait(for: [loaded], timeout: 15)
    XCTAssertNil(delegate.error)

    // A positive decoded image prevents ATS/network failure from masquerading
    // as successful blocking. The explicit redirect request is also required.
    let decoded = expectation(description: "Allowed image is actually decoded")
    var imageState: [String: Any]?
    web.evaluateJavaScript("({allowed:document.getElementById('allowed').naturalWidth,redirect:document.getElementById('redirect').naturalWidth,unknown:document.getElementById('unknown').naturalWidth,title:document.title,styles:Array.from(document.styleSheets).filter(function(s){return !!s.href}).length,font:getComputedStyle(document.body).fontFamily})") { result, error in
      XCTAssertNil(error)
      imageState = result as? [String: Any]
      decoded.fulfill()
    }
    wait(for: [decoded], timeout: 5)
    XCTAssertEqual(imageState?["allowed"] as? Int, 4)
    XCTAssertEqual(imageState?["redirect"] as? Int, 0)
    XCTAssertEqual(imageState?["unknown"] as? Int, 0)
    XCTAssertEqual(imageState?["title"] as? String, "Owned resource-rule fixture")
    XCTAssertEqual(imageState?["styles"] as? Int, 1)
    XCTAssertEqual(imageState?["font"] as? String, "sans-serif")
    let counts = server.counts
    XCTAssertEqual(counts["/document"], 1)
    XCTAssertEqual(counts["/allowed.png"], 1)
    XCTAssertEqual(counts["/allowed.css"], 1)
    XCTAssertEqual(counts["/redirect.png"], 1)
    for path in ["/forbidden.png", "/unknown.png", "/unknown.css", "/css-forbidden.png", "/frame", "/script.js"] {
      XCTAssertEqual(counts[path, default: 0], 0, "Unexpected network request: \(path)")
    }
    let decodedWidth = imageState?["allowed"] as? Int ?? 0
    print("WINGMAN_WEBKIT_RULE_EVIDENCE \(counts) allowedImageWidth=\(decodedWidth) externalStyles=1 font=sans-serif forbiddenRequests=0")
  }

  /// Uses the production's query-independent rules and navigation predicate.
  /// All documents here are synthetic loopback fixtures, never search results.
  @MainActor
  func testStrictSearchRulesAndNavigationRejectFramesAndRedirects() throws {
    let ready = expectation(description: "Owned search fixture server starts")
    let server = try ContentRuleFixtureServer(png: Data(), ready: ready)
    defer { server.stop() }
    wait(for: [ready], timeout: 5)
    let origin = "http://127.0.0.1:\(try XCTUnwrap(server.port))"
    let document = origin + "/lite/?q=fixture&kp=1"
    let rules = try XCTUnwrap(strictSearchContentRuleJSON(
      documentOrigin: origin, styleURL: origin + "/search.css"
    ))
    XCTAssertFalse(rules.contains("q=fixture"), "Rules must not persist a query")
    let identifier = "wingman-xctest-search-rules-\(UUID().uuidString)"
    defer { WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in } }
    let compiled = expectation(description: "Production search rule JSON compiles")
    var list: WKContentRuleList?
    var compileError: Error?
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: identifier, encodedContentRuleList: rules
    ) { result, error in
      list = result; compileError = error; compiled.fulfill()
    }
    wait(for: [compiled], timeout: 10)
    XCTAssertNil(compileError)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.userContentController.add(try XCTUnwrap(list))
    let loaded = expectation(description: "Synthetic search document loads")
    let delegate = StrictSearchNavigationObserver(currentURL: document, loaded: loaded)
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
    web.navigationDelegate = delegate
    defer { web.stopLoading(); web.navigationDelegate = nil; web.removeFromSuperview() }
    web.load(URLRequest(url: try XCTUnwrap(URL(string: document))))
    wait(for: [loaded], timeout: 15)
    XCTAssertNil(delegate.error)
    let inspected = expectation(description: "Synthetic document and CSS positive controls")
    var state: [String: Any]?
    web.evaluateJavaScript("({title:document.title,font:getComputedStyle(document.body).fontFamily,styles:Array.from(document.styleSheets).filter(function(s){return !!s.href}).length,inputDisplay:getComputedStyle(document.getElementById('query')).display})") { result, error in
      XCTAssertNil(error); state = result as? [String: Any]; inspected.fulfill()
    }
    wait(for: [inspected], timeout: 5)
    XCTAssertEqual(state?["title"] as? String, "Owned search fixture")
    XCTAssertEqual(state?["font"] as? String, "sans-serif")
    XCTAssertEqual(state?["styles"] as? Int, 1)
    XCTAssertEqual(state?["inputDisplay"] as? String, "none")
    XCTAssertEqual(server.targets["/lite/?q=fixture&kp=1"], 1)
    XCTAssertEqual(server.counts["/search.css"], 1)
    XCTAssertEqual(server.targets["/lite/?q=frame&kp=1", default: 0], 0)
    for path in ["/unknown.png", "/unknown.css", "/script.js", "/t/sl_l"] {
      XCTAssertEqual(server.counts[path, default: 0], 0, "Unexpected search fixture request: \(path)")
    }
    XCTAssertGreaterThan(delegate.deniedSubframes, 0)

    // A main-document 302 targets a URL matching the broad static rule pattern.
    // The production navigation/lifecycle gate must still stop that request.
    let redirectURL = origin + "/lite/?q=redirect&kp=1"
    let redirected = expectation(description: "Owned redirect is rejected")
    let redirectDelegate = StrictSearchNavigationObserver(currentURL: redirectURL, loaded: redirected)
    web.navigationDelegate = redirectDelegate
    web.load(URLRequest(url: try XCTUnwrap(URL(string: redirectURL))))
    wait(for: [redirected], timeout: 15)
    // Let canceled local network work drain before taking the final receipt;
    // an early delegate callback alone is not evidence of zero target traffic.
    let drained = expectation(description: "Canceled local redirect work drains")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { drained.fulfill() }
    wait(for: [drained], timeout: 2)
    XCTAssertTrue(redirectDelegate.sawRedirect || redirectDelegate.deniedMainFrames > 0)
    XCTAssertEqual(server.targets["/lite/?q=redirect&kp=1"], 1)
    XCTAssertEqual(server.targets["/lite/?q=redirect-target&kp=1", default: 0], 0)

    // Both POST and reusing the initial grant are denied even for the same URL.
    XCTAssertFalse(protectedAllowsInitialNavigation(isMainFrame: true, method: "POST", requestedURL: document, currentURL: document, initial: true, scopePermitted: true))
    XCTAssertFalse(protectedAllowsInitialNavigation(isMainFrame: true, method: "GET", requestedURL: document, currentURL: document, initial: false, scopePermitted: true))
    print("WINGMAN_SEARCH_WEBKIT_EVIDENCE \(server.targets) cssPositive=1 subframesDenied=\(delegate.deniedSubframes) redirectTargetRequests=\(server.targets["/lite/?q=redirect-target&kp=1", default: 0])")
  }
}

@MainActor
private final class ActivityRecordingWebView: WKWebView {
  var playbackSuspension = [Bool]()
  var cameraChanges = [WKMediaCaptureState]()
  var microphoneChanges = [WKMediaCaptureState]()
  var closedPresentations = 0
  override func setAllMediaPlaybackSuspended(_ suspended: Bool, completionHandler: (@MainActor @Sendable () -> Void)? = nil) {
    playbackSuspension.append(suspended); completionHandler?()
  }
  override func setCameraCaptureState(_ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)? = nil) {
    cameraChanges.append(state); completionHandler?()
  }
  override func setMicrophoneCaptureState(_ state: WKMediaCaptureState, completionHandler: (@MainActor @Sendable () -> Void)? = nil) {
    microphoneChanges.append(state); completionHandler?()
  }
  override func closeAllMediaPresentations(completionHandler: (@MainActor @Sendable () -> Void)? = nil) {
    closedPresentations += 1; completionHandler?()
  }
}

private final class StrictSearchNavigationObserver: NSObject, WKNavigationDelegate {
  let currentURL: String
  let loaded: XCTestExpectation
  private var initial = true
  private var finished = false
  var deniedSubframes = 0
  var deniedMainFrames = 0
  var sawRedirect = false
  var error: Error?
  init(currentURL: String, loaded: XCTestExpectation) { self.currentURL = currentURL; self.loaded = loaded }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let raw = action.request.url?.absoluteString ?? ""
    let main = action.targetFrame?.isMainFrame == true
    let allowed = protectedAllowsInitialNavigation(
      isMainFrame: main, method: action.request.httpMethod,
      requestedURL: raw, currentURL: currentURL,
      initial: initial && action.navigationType == .other,
      scopePermitted: raw == currentURL
    )
    if allowed { initial = false; decisionHandler(.allow) }
    else {
      if main { deniedMainFrames += 1 } else { deniedSubframes += 1 }
      decisionHandler(.cancel)
      if main { finish(nil) }
    }
  }
  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    sawRedirect = true; webView.stopLoading(); finish(nil)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
  private func finish(_ failure: Error?) {
    guard !finished else { return }
    finished = true; error = failure; loaded.fulfill()
  }
}

private final class ContentRuleNavigationObserver: NSObject, WKNavigationDelegate {
  let loaded: XCTestExpectation
  private var finished = false
  var error: Error?
  init(loaded: XCTestExpectation) { self.loaded = loaded }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
  private func finish(_ failure: Error?) {
    guard !finished else { return }
    finished = true
    error = failure
    loaded.fulfill()
  }
}

/// A bounded, request-counting server that exists only in the XCTest target.
/// It never proxies a request or contacts an external host.
private final class PopupTestMessenger: NSObject, FlutterBinaryMessenger {
  private var handler: FlutterBinaryMessageHandler?
  var onEvent: ((FlutterMethodCall) -> Void)?
  var errors: [FlutterError?] = []
  func send(onChannel channel: String, message: Data?) { if let data = message { onEvent?(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(data)) } }
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) { send(onChannel: channel, message: message); callback?(nil) }
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { self.handler = handler; return 1 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) { handler = nil }
  func invoke(_ method: String, _ args: [String: Any]) {
    let codec = FlutterStandardMethodCodec.sharedInstance()
    handler?(codec.encode(FlutterMethodCall(methodName: method, arguments: args))) { data in
      guard let data = data else { return }; self.errors.append(codec.decodeEnvelope(data) as? FlutterError)
    }
  }
}

private final class ContentRuleFixtureServer {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "wingman.tests.owned-content-rules")
  private let png: Data
  private var requestCounts: [String: Int] = [:]
  private var targetCounts: [String: Int] = [:]
  private var connections: [ObjectIdentifier: NWConnection] = [:]
  private(set) var port: UInt16?
  private(set) var startError: String?
  var counts: [String: Int] { queue.sync { requestCounts } }
  var targets: [String: Int] { queue.sync { targetCounts } }

  init(png: Data, ready: XCTestExpectation) throws {
    self.png = png
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    listener = try NWListener(using: parameters)
    var announced = false
    listener.stateUpdateHandler = { [weak self] state in
      guard let self = self, !announced else { return }
      switch state {
      case .ready:
        self.port = self.listener.port?.rawValue
        announced = true
        ready.fulfill()
      case .failed(let error):
        self.startError = error.localizedDescription
        announced = true
        ready.fulfill()
      default: break
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      guard let self = self else { connection.cancel(); return }
      self.connections[ObjectIdentifier(connection)] = connection
      connection.start(queue: self.queue)
      self.receive(connection, buffer: Data())
    }
    listener.start(queue: queue)
  }

  func stop() {
    listener.cancel()
    queue.sync {
      connections.values.forEach { $0.cancel() }
      connections.removeAll()
    }
  }

  private func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] bytes, _, complete, error in
      guard let self = self else { connection.cancel(); return }
      var accumulated = buffer
      accumulated.append(bytes ?? Data())
      guard accumulated.count <= 16 * 1024, error == nil else { self.close(connection); return }
      if let header = String(data: accumulated, encoding: .utf8), header.contains("\r\n\r\n") {
        let parts = header.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard parts.count == 3, ["GET", "POST"].contains(String(parts[0])) else { self.close(connection); return }
        let boundary = header.range(of: "\r\n\r\n")!
        let body = String(header[boundary.upperBound...])
        let lengthLine = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
        let expectedLength = lengthLine.flatMap { Int($0.components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)) } ?? 0
        if body.utf8.count < expectedLength { self.receive(connection, buffer: accumulated); return }
        let target = String(parts[1])
        let path = target.components(separatedBy: "?")[0]
        self.requestCounts[path, default: 0] += 1
        self.targetCounts[target, default: 0] += 1
        self.respond(connection, path: path, target: target, method: String(parts[0]), requestBody: body)
      } else if !complete {
        self.receive(connection, buffer: accumulated)
      } else { self.close(connection) }
    }
  }

  private func respond(_ connection: NWConnection, path: String, target: String, method: String, requestBody: String) {
    let status: String
    let type: String
    let body: Data
    var extra = ""
    switch path {
    case "/popup-parent":
      status = "200 OK"; type = "text/html"; body = Data("""
        <!doctype html><title>Popup parent</title><p id="result">Waiting</p>
        <button id="get-child" onclick="window.open('/popup-get','get-child')">Open GET</button>
        <form action="/popup-post" method="post" target="post-child"><input name="marker" value="synthetic-post-body"><button id="post-child">Open POST</button></form>
        <script>addEventListener('message',e=>{if(e.origin===location.origin)document.getElementById('result').textContent=e.data})</script>
        """.utf8)
    case "/popup-get", "/popup-post":
      status = "200 OK"; type = "text/html"; body = Data("""
        <!doctype html><title>Popup child</title><p>\(requestBody)</p>
        <script>if(window.opener)window.opener.postMessage('\(method) opener retained',location.origin)</script>
        """.utf8)
    case "/lite/":
      type = "text/html; charset=utf-8"
      if target == "/lite/?q=redirect&kp=1" {
        status = "302 Found"; body = Data()
        extra = "Location: /lite/?q=redirect-target&kp=1\r\n"
      } else {
        status = "200 OK"
        body = Data("""
          <!doctype html><html><head><title>Owned search fixture</title>
          <link rel="stylesheet" href="/search.css"><link rel="stylesheet" href="/unknown.css">
          </head><body><h1>Owned synthetic search fixture</h1>
          <form method="post" action="/lite/"><input id="query" name="q" value="fixture"><input name="kp" value="-2"></form>
          <a href="/destination">Synthetic result link</a>
          <iframe src="/lite/?q=frame&amp;kp=1"></iframe>
          <img src="/unknown.png"><img src="/t/sl_l"><script src="/script.js"></script>
          </body></html>
          """.utf8)
      }
    case "/search.css":
      status = "200 OK"; type = "text/css"; body = Data("body{font-family:sans-serif}".utf8)
    case "/document":
      status = "200 OK"; type = "text/html; charset=utf-8"
      body = Data("""
        <!doctype html><html><head><title>Owned resource-rule fixture</title>
        <link rel="stylesheet" href="/allowed.css?modules=one%7Ctwo%2Cthree&amp;only=styles"><link rel="stylesheet" href="/unknown.css">
        </head><body><h1>Owned resource-rule fixture</h1>
        <img id="allowed" src="/allowed.png"><img id="redirect" src="/redirect.png">
        <img id="unknown" src="/unknown.png"><div class="probe">Background probe</div>
        <iframe src="/frame"></iframe><script src="/script.js"></script>
        </body></html>
        """.utf8)
    case "/allowed.css":
      status = "200 OK"; type = "text/css"
      body = Data("body{font-family:sans-serif}.probe{background-image:url('/css-forbidden.png')}".utf8)
    case "/redirect.png":
      status = "302 Found"; type = "image/png"; body = Data()
      extra = "Location: /forbidden.png\r\n"
    case "/allowed.png", "/forbidden.png", "/unknown.png", "/css-forbidden.png":
      status = "200 OK"; type = "image/png"; body = png
    case let path where path.hasPrefix("/consumer-allowed/") || path.hasPrefix("/promotion") || path.hasPrefix("//promotion"):
      status = "200 OK"; type = "image/png"; body = png
    default:
      status = "200 OK"; type = "text/plain"; body = Data("Unexpected fixture request".utf8)
    }
    let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\(extra)\r\n"
    var response = Data(head.utf8)
    response.append(body)
    connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.close(connection) })
  }

  private func close(_ connection: NWConnection) {
    connection.cancel()
    connections.removeValue(forKey: ObjectIdentifier(connection))
  }
}
