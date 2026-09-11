@testable import Runner
import Network
import UIKit
import WebKit
import XCTest

final class RunnerTests: XCTestCase {
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
        guard parts.count == 3, parts[0] == "GET" else { self.close(connection); return }
        let target = String(parts[1])
        let path = target.components(separatedBy: "?")[0]
        self.requestCounts[path, default: 0] += 1
        self.targetCounts[target, default: 0] += 1
        self.respond(connection, path: path, target: target)
      } else if !complete {
        self.receive(connection, buffer: accumulated)
      } else { self.close(connection) }
    }
  }

  private func respond(_ connection: NWConnection, path: String, target: String) {
    let status: String
    let type: String
    let body: Data
    var extra = ""
    switch path {
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
