import Flutter
import UIKit
import WebKit
import CryptoKit

/// Scriptless website rendering with an immutable, exact-URL resource allow set.
/// The legacy browser channel has no route to this factory or its policy.
final class ProtectedWebBridge: NSObject, FlutterPlatformViewFactory {
  static let viewType = "wingman/protected-web"
  static let catalogAsset = "assets/policy/live_sites.json"
  // Updated only with the packaged reviewed catalog, never from a method call.
  static let catalogSHA256 = "7937170f4c5605faff4e7fbfcc0ea4f27623b05a75c84e6adc8aba2243f965c1"
  let channel: FlutterMethodChannel
  private let catalog: ProtectedCatalog
  private var views: [Int64: WeakProtectedWebView] = [:]
  private var retainedViews: [ProtectedWebView] { views.values.compactMap { $0.value } }
  private var platformSupported: Bool { if #available(iOS 18.4, *) { return true }; return false }
  private var ready = false
  private var foreground = true
  private var handoffBlocked = false
  private var cleanupPending = false
  private var compiled: [String: WKContentRuleList] = [:]
  private var preparing = false
  private var ruleCompilationCount = 0
  private var preparationWaiters: [() -> Void] = []

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "wingman/protected-browser", binaryMessenger: registrar.messenger())
    let key = registrar.lookupKey(forAsset: Self.catalogAsset)
    catalog = ProtectedCatalog(path: Bundle.main.path(forResource: key, ofType: nil))
    super.init()
    registrar.register(self, withId: Self.viewType)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let values = args as? [String: Any] ?? [:]
    let view = ProtectedWebView(frame: frame, id: viewId, tabId: values["tabId"] as? String ?? "", privateMode: values["private"] as? Bool == true, bridge: self)
    views = views.filter { $0.value.value != nil }
    views[viewId] = WeakProtectedWebView(view)
    return view
  }
  func quarantineCompleted(completion: @escaping () -> Void) {
    if ready && catalog.valid { completion(); return }
    preparationWaiters.append(completion)
    guard !preparing else { return }
    preparing = true
    // Compile every public bundled site at startup. A private visit never creates
    // a durable site-specific rule-store record or reveals a browsing choice.
    let group = DispatchGroup()
    var prepared: [String: WKContentRuleList] = [:]
    var failed = !platformSupported || !catalog.valid
    for site in catalog.reviewedSites {
      guard let rules = catalog.ruleList(for: site) else { failed = true; continue }
      group.enter()
      ruleCompilationCount += 1
      WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "wingman-reviewed-\(Self.catalogSHA256)-\(site.id)", encodedContentRuleList: rules) { list, error in
        DispatchQueue.main.async {
          if let list = list, error == nil { prepared[site.id] = list } else { failed = true }
          group.leave()
        }
      }
    }
    group.notify(queue: .main) {
      self.compiled = prepared
      self.ready = !failed && self.catalog.valid && prepared.count == self.catalog.reviewedSites.count
      self.preparing = false
      let waiters = self.preparationWaiters
      self.preparationWaiters.removeAll()
      waiters.forEach { $0() }
    }
  }
  func cleanupStarted() { cleanupPending = true; closeAll() }
  func cleanupFinished() { cleanupPending = false }
  func hideAll() { handoffBlocked = true; closeAll() }
  func restoreOwner() { handoffBlocked = false }
  func pauseAll() { foreground = false; closeAll() }
  func resume() { foreground = true }
  func closeAll() { retainedViews.forEach { $0.release() } }
  fileprivate func remove(_ id: Int64) { views.removeValue(forKey: id) }
  fileprivate var mayOpen: Bool { platformSupported && ready && foreground && !handoffBlocked && !cleanupPending && catalog.valid }
  fileprivate func approved(_ url: String) -> ProtectedSite? { mayOpen ? catalog.document(protectedCanonical(url) ?? "") : nil }
  fileprivate func emit(_ event: String, _ data: [String: Any]) { channel.invokeMethod(event, arguments: data) }
  private func error(_ result: FlutterResult) { result(FlutterError(code: "protected_navigation_denied", message: "This page is outside the current reviewed website scope.", details: nil)) }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "capabilities" {
      let supported = platformSupported && ready && !cleanupPending && catalog.valid
      result(["supported": supported, "privateAvailable": supported, "mode": "reviewedScriptlessWeb", "reason": supported ? NSNull() as Any : (!platformSupported ? "Protected visual browsing requires iOS 18.4 or later." : "Reviewed website protection is unavailable.") as Any ]); return
    }
    if call.method == "state", args["viewId"] == nil {
      result(["views": retainedViews.filter { $0.hasRenderer }.count, "ready": ready, "foreground": foreground, "handoffBlocked": handoffBlocked, "cleanupPending": cleanupPending, "catalogValid": catalog.valid, "preparedRuleSets": compiled.count, "ruleCompilationCount": ruleCompilationCount]); return
    }
    guard let id = (args["viewId"] as? NSNumber)?.int64Value, let view = views[id]?.value else { error(result); return }
    switch call.method {
    case "open", "reload":
      let raw = args["url"] as? String ?? view.currentURL
      guard mayOpen, let request = (args["requestId"] as? NSNumber)?.int64Value,
        let url = protectedCanonical(raw), let site = approved(url), request > view.requestId else { error(result); return }
      view.release()
      view.begin(url: raw, request: request, site: site)
      guard let list = compiled[site.id] else { view.fail(); error(result); return }
      view.open(list: list); result(nil)

    case "close": view.release(); views.removeValue(forKey: id); result(nil)
    case "stop": view.release(); result(nil)
    case "setActive":
      if args["active"] as? Bool != true { view.release() }
      // A newly active tab must explicitly open again through current policy.
      result(nil)
    case "state": view.diagnosticState(result)
    default: result(FlutterError(code: "protected_method_unavailable", message: "This browser operation is unavailable.", details: nil))
    }
  }
}

private final class WeakProtectedWebView {
  weak var value: ProtectedWebView?
  init(_ value: ProtectedWebView) { self.value = value }
}

private final class ProtectedWebView: NSObject, FlutterPlatformView, WKNavigationDelegate, WKUIDelegate {
  let id: Int64
  let tabId: String
  let privateMode: Bool
  weak var bridge: ProtectedWebBridge?
  private let container: UIView
  private var web: WKWebView?
  private var site: ProtectedSite?
  private var expiryTimer: Timer?
  private var progressObservation: NSKeyValueObservation?
  private(set) var currentURL = ""
  private(set) var requestId: Int64 = 0
  private(set) var pending = false
  private var loading = false
  private var progress = 0
  private var errorText: String?
  private var approvedInitialRequest = false
  var hasRenderer: Bool { web != nil }
  var state: [String: Any] { ["viewId": id, "requestId": requestId, "url": currentURL, "title": site?.title ?? "", "progress": progress, "isLoading": loading, "error": errorText ?? NSNull() as Any, "blockedResources": NSNull(), "loadedResources": NSNull(), "bytesReceived": NSNull(), "hasRenderer": hasRenderer, "private": privateMode, "javascript": web?.configuration.defaultWebpagePreferences.allowsContentJavaScript ?? false, "resourceRulesInstalled": hasRenderer] }
  init(frame: CGRect, id: Int64, tabId: String, privateMode: Bool, bridge: ProtectedWebBridge) {
    self.id = id; self.tabId = tabId; self.privateMode = privateMode; self.bridge = bridge
    container = UIView(frame: frame)
    container.backgroundColor = .systemBackground
    super.init()
  }
  func view() -> UIView { container }
  deinit { release(); bridge?.remove(id) }
  private func emit() { bridge?.emit("pageState", state) }
  func diagnosticState(_ result: @escaping FlutterResult) {
    guard let view = web else { result(state); return }
    let generation = requestId
    // A fixed read-only expression returns counts, never text, URLs or page data.
    view.evaluateJavaScript("({externalStyleSheets:Array.from(document.styleSheets).filter(function(s){return !!s.href}).length,imagesTotal:document.images.length,imagesComplete:Array.from(document.images).filter(function(i){return i.complete&&i.naturalWidth>0&&i.naturalHeight>0}).length})") { [weak self, weak view] value, error in
      guard let self = self else { result([:]); return }
      var data = self.state
      if view === self.web, generation == self.requestId, error == nil, let counts = value as? [String: Any] {
        data["externalStyleSheets"] = counts["externalStyleSheets"] as? Int ?? NSNull() as Any
        data["imagesTotal"] = counts["imagesTotal"] as? Int ?? NSNull() as Any
        data["imagesComplete"] = counts["imagesComplete"] as? Int ?? NSNull() as Any
      } else { data["externalStyleSheets"] = NSNull(); data["imagesTotal"] = NSNull(); data["imagesComplete"] = NSNull() }
      result(data)
    }
  }
  func begin(url: String, request: Int64, site: ProtectedSite) {
    currentURL = url; requestId = request; self.site = site
    pending = true; loading = true; progress = 0; errorText = nil
    emit()
  }
  func open(list: WKContentRuleList) {
    guard pending, let bridge = bridge, bridge.mayOpen, bridge.approved(currentURL) != nil,
      !tabId.isEmpty, tabId.count <= 100, let url = URL(string: currentURL), let site = site else { fail(); return }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.preferences.isFraudulentWebsiteWarningEnabled = true
    configuration.preferences.isTextInteractionEnabled = false
    configuration.allowsInlineMediaPlayback = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    configuration.suppressesIncrementalRendering = true
    configuration.userContentController.add(list)
    let view = WKWebView(frame: container.bounds, configuration: configuration)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.navigationDelegate = self; view.uiDelegate = self
    view.customUserAgent = "Wingman/0.8 (Protected Visual Browsing)"
    view.allowsLinkPreview = false
    view.allowsBackForwardNavigationGestures = false
    if #available(iOS 16.4, *) { view.isInspectable = false }
    web = view
    progressObservation = view.observe(\.estimatedProgress, options: [.new]) { [weak self] changedView, change in
      guard let self = self, changedView === self.web else { return }; self.progress = Int((change.newValue ?? 0) * 100); self.emit()
    }
    expiryTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, site.expires.timeIntervalSinceNow), repeats: false) { [weak self] _ in self?.fail() }
    container.addSubview(view)
    approvedInitialRequest = true
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
    request.httpMethod = "GET"
    request.setValue("1", forHTTPHeaderField: "DNT")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    view.load(request)
  }
  func release() {
    pending = false; loading = false; approvedInitialRequest = false
    expiryTimer?.invalidate(); expiryTimer = nil
    progressObservation?.invalidate(); progressObservation = nil
    web?.stopLoading(); web?.isHidden = true; web?.navigationDelegate = nil; web?.uiDelegate = nil
    web?.removeFromSuperview(); web = nil
  }
  func fail() { release(); errorText = "This page could not load within its reviewed website scope."; emit() }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard webView === web, pending, bridge?.mayOpen == true, action.targetFrame?.isMainFrame == true,
      action.request.httpMethod == "GET", let raw = action.request.url?.absoluteString,
      let url = protectedCanonical(raw) else { decisionHandler(.cancel); return }
    if approvedInitialRequest && action.navigationType == .other && url == protectedCanonical(currentURL) && bridge?.approved(url) != nil {
      approvedInitialRequest = false; decisionHandler(.allow); return
    }
    decisionHandler(.cancel)
    if action.navigationType == .linkActivated {
      bridge?.emit("navigationRequested", ["viewId": id, "requestId": requestId, "url": raw])
    }
  }
  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    // Even an allowlisted redirect is not followed as an implicit new authorization.
    if webView === web { fail() }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard webView === web, pending, bridge?.mayOpen == true, response.isForMainFrame,
      let url = response.response.url?.absoluteString, protectedCanonical(url) == protectedCanonical(currentURL),
      let entry = site?.documents[protectedCanonical(currentURL) ?? ""], let http = response.response as? HTTPURLResponse,
      http.statusCode == 200, entry.mimeTypes.contains(response.response.mimeType ?? ""),
      response.canShowMIMEType, response.response.expectedContentLength <= entry.maxBytes,
      http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") != true else {
      decisionHandler(.cancel); if webView === web { fail() }; return
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard webView === web else { return }
    guard pending, bridge?.approved(currentURL) != nil else { fail(); return }
    loading = false; progress = 100; emit()
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === web { fail() } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === web { fail() } }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === web { release(); bridge?.emit("rendererGone", ["viewId": id, "requestId": requestId]) } }
  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil) }
    else { completionHandler(.cancelAuthenticationChallenge, nil) }
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
  @available(iOS 18.4, *)
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) { completionHandler(nil) }
  func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) { completionHandler(nil) }
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
}

private struct ProtectedEntry {
  let url: String
  let type: String
  let mimeTypes: Set<String>
  let maxBytes: Int64
}
private struct ProtectedSite {
  let id: String
  let title: String
  let expires: Date
  let documents: [String: ProtectedEntry]
  let resources: [String: ProtectedEntry]
}
private final class ProtectedCatalog {
  private var sites: [ProtectedSite] = []
  private var expires = Date.distantPast
  private var privacyDomains = Set<String>()
  var valid: Bool { Date() < expires && sites.contains { Date() < $0.expires } }
  var reviewedSites: [ProtectedSite] { sites.sorted { $0.id < $1.id } }
  init(path: String?) {
    do {
      guard let path = path else { return }
      let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
      guard bytes.count <= 512 * 1024,
        SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == ProtectedWebBridge.catalogSHA256,
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
        json["schemaVersion"] as? Int == 1, json["policyVersion"] as? Int == 1,
        (json["sequence"] as? Int ?? 0) > 0,
        let expiry = protectedDate(json["expiresAt"]), let reviewed = protectedDate(json["reviewedAt"]), reviewed <= Date(),
        let rows = json["sites"] as? [[String: Any]], let privacy = json["privacy"] as? [String: Any],
        let domains = privacy["domains"] as? [String] else { return }
      expires = expiry; privacyDomains = Set(domains)
      for row in rows where row["enabled"] as? Bool == true {
        guard let id = row["id"] as? String, let title = row["title"] as? String,
          let expiry = protectedDate(row["expiresAt"]), let reviewed = protectedDate(row["reviewedAt"]), reviewed <= Date(),
          let docs = entries(row["documents"], type: "document"), let resources = entries(row["resources"], type: nil) else { sites = []; return }
        sites.append(ProtectedSite(id: id, title: title, expires: min(expiry, expires), documents: docs, resources: resources))
      }
    } catch { sites = [] }
  }
  private func entries(_ value: Any?, type: String?) -> [String: ProtectedEntry]? {
    guard let values = value as? [[String: Any]] else { return nil }
    var results: [String: ProtectedEntry] = [:]
    for row in values {
      guard let url = row["url"] as? String, protectedCanonical(url) == url,
        let mime = row["mimeTypes"] as? [String], !mime.isEmpty,
        let max = row["maxBytes"] as? Int, max > 0 && max <= 4 * 1024 * 1024,
        let kind = type ?? row["type"] as? String, ["document", "image", "styleSheet", "font"].contains(kind), results[url] == nil else { return nil }
      results[url] = ProtectedEntry(url: url, type: kind, mimeTypes: Set(mime), maxBytes: Int64(max))
    }
    return results
  }
  func document(_ url: String) -> ProtectedSite? { valid ? sites.first { Date() < $0.expires && $0.documents[url] != nil } : nil }
  func ruleList(for site: ProtectedSite) -> String? {
    protectedContentRuleJSON(documents: Array(site.documents.keys), resources: site.resources.mapValues { $0.type }, privacyDomains: Array(privacyDomains))
  }
}

/// Pure rule construction is independently exercised by the native XCTest target.
/// Production callers supply only the hash-pinned catalog; this is not a platform channel.
func protectedContentRuleJSON(documents: [String], resources: [String: String], privacyDomains: [String]) -> String? {
  var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
  var entries = resources
  for url in documents { entries[url] = "document" }
  for (url, kind) in entries.sorted(by: { $0.key < $1.key }) {
    let type = kind == "styleSheet" ? "style-sheet" : kind
    rules.append(["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: url) + "$", "url-filter-is-case-sensitive": true, "resource-type": [type]], "action": ["type": "ignore-previous-rules"]])
  }
  // A maintained deny-only list cannot grant permission to any destination.
  for domain in privacyDomains.sorted() {
    rules.append(["trigger": ["url-filter": "^https://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]])
  }
  rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]])
  // Scriptless reading has no supported editable forms; hide focusable editors before interaction.
  rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "input,textarea,select,[contenteditable]"]])
  guard let bytes = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: bytes, encoding: .utf8) else { return nil }
  return json

}
private func protectedDate(_ input: Any?) -> Date? {
  guard let value = input as? String else { return nil }
  return ISO8601DateFormatter().date(from: value)
}
private func protectedCanonical(_ raw: String) -> String? {
  guard !raw.isEmpty, raw.utf8.count <= 16_384, raw.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 && $0 != "\\" }),
    var components = URLComponents(string: raw), components.scheme == "https", components.user == nil, components.password == nil,
    components.port == nil, let host = components.host, !host.isEmpty, host == host.lowercased(), !host.hasSuffix("."),
    components.percentEncodedPath.range(of: "%(00|0a|0d|2f|5c)", options: .regularExpression.union(.caseInsensitive)) == nil, !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
  components.fragment = nil
  if components.path.isEmpty { components.path = "/" }
  return components.string
}
