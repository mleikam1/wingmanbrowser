import Flutter
import UIKit
import WebKit
import CryptoKit
import UniformTypeIdentifiers

/// Native consumer transport. WebKit owns TLS, origins, cookies, storage and JS.
/// This channel is only reachable by Flutter; no WKScriptMessageHandler is installed.
final class ProtectedWebBridge: NSObject, FlutterPlatformViewFactory {
  static let viewType = "wingman/protected-web"
  static let protectionAsset = "assets/policy/consumer_protection.json"
  static let protectionSHA256 = "f397d8f87a02fbb7754ce9c77931f740ba10271370e1e09f8402607bef59098f"
  let channel: FlutterMethodChannel
  private var baseline: ConsumerNativePolicy
  private let updateKeys: [String: String]
  private var pendingUpdate: ConsumerNativeUpdate?
  private var revertUpdate: (token: String, policy: ConsumerNativePolicy, rules: [WKContentRuleList], receipt: [String: Any], recoveryRequired: Bool)?
  private var activeDigest = ProtectedWebBridge.protectionSHA256
  private var updateRecoveryRequired = false
  private var views: [Int64: WeakProtectedWebView] = [:]
  private var retainedViews: [ProtectedWebView] { views.values.compactMap { $0.value } }
  private var ready = false
  private var preparing = false
  private var foreground = true
  private var handoffBlocked = false
  private var cleanupPending = false
  private var compiled: [WKContentRuleList] = []
  private var preparationWaiters: [() -> Void] = []
  private var compilationCount = 0
  private var pendingWindows: [String: ConsumerPendingWindow] = [:]
  private var nextPendingViewId: Int64 = -1

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "wingman/protected-browser", binaryMessenger: registrar.messenger())
    let key = registrar.lookupKey(forAsset: Self.protectionAsset)
    baseline = ConsumerNativePolicy(path: Bundle.main.path(forResource: key, ofType: nil), expectedDigest: Self.protectionSHA256)
    let updateKeyAsset = registrar.lookupKey(forAsset: "assets/policy/consumer_update_keys.json")
    if let path = Bundle.main.path(forResource: updateKeyAsset, ofType: nil), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], json["schemaVersion"] as? Int == 1 {
      updateKeys = json["keys"] as? [String: String] ?? [:]
    } else { updateKeys = [:] }
    super.init()
    do {
      let receipt = try ConsumerNativeUpdate.receipt()
      updateRecoveryRequired = (receipt["sequence"] as? Int ?? 1) > 1
    } catch { updateRecoveryRequired = true }
    registrar.register(self, withId: Self.viewType)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }
  #if DEBUG
  /// Test-host dependency injection; production always loads and compiles the
  /// pinned policy through the registrar and startup recovery path above.
  init(testPolicy: ConsumerNativePolicy, rules: [WKContentRuleList], messenger: FlutterBinaryMessenger) {
    baseline = testPolicy; compiled = rules; updateKeys = [:]; ready = testPolicy.valid && !rules.isEmpty
    channel = FlutterMethodChannel(name: "wingman/protected-browser", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }
  #endif
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let values = args as? [String: Any] ?? [:]
    if let token = values["windowToken"] as? String, let pending = pendingWindows.removeValue(forKey: token) {
      let view = pending.view
      if mayOpen, foreground, pending.isCurrent,
        (values["edition"] as? String) == "consumer", view.privateMode == (values["private"] as? Bool == true),
        let tabId = values["tabId"] as? String, !tabId.isEmpty, tabId.count <= 100, view.matchesRestrictions(values) {
        view.adoptIdentity(viewId: viewId, tabId: tabId, frame: frame)
        views[viewId] = WeakProtectedWebView(view)
        return view
      }
      view.release()
    }
    let view = ProtectedWebView(frame: frame, id: viewId, tabId: values["tabId"] as? String ?? "", privateMode: values["private"] as? Bool == true,
      consumer: (values["edition"] as? String ?? "unknown") == "consumer", restrictions: values, bridge: self)
    views = views.filter { $0.value.value != nil }
    views[viewId] = WeakProtectedWebView(view)
    return view
  }
  /// Startup only prepares pinned protection. The native migration caller owns
  /// the one-time legacy purge; this never clears valid consumer sessions.
  func quarantineCompleted(completion: @escaping () -> Void) {
    if ready { completion(); return }
    preparationWaiters.append(completion)
    guard !preparing else { return }
    preparing = true
    guard baseline.valid else { finishPreparation([]); return }
    let ruleGroups = baseline.contentRuleGroups()
    var lists: [WKContentRuleList] = []
    func prepare(_ index: Int) {
      guard index < ruleGroups.count else { self.finishPreparation(lists); return }
      let identifier = consumerContentRuleIdentifier(digest: Self.protectionSHA256, index: index, count: ruleGroups.count)
      WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { existing, _ in
        if let existing = existing { lists.append(existing); prepare(index + 1); return }
        self.compilationCount += 1
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: ruleGroups[index]) { list, error in
          guard let list = list, error == nil else { self.finishPreparation([]); return }
          lists.append(list)
          #if DEBUG
          print("[Wingman protection] prepared \(index + 1)/\(ruleGroups.count)")
          #endif
          prepare(index + 1)
        }
      }
    }
    prepare(0)
  }
  private func finishPreparation(_ lists: [WKContentRuleList]) {
    compiled = lists; ready = baseline.valid && !lists.isEmpty; preparing = false
    let waiters = preparationWaiters; preparationWaiters.removeAll(); waiters.forEach { $0() }
  }
  func cleanupStarted() { cleanupPending = true; closeAll() }
  func cleanupFinished() { cleanupPending = false }
  func hideAll() { handoffBlocked = true; closeAll() }
  func restoreOwner() { handoffBlocked = false }
  func pauseAll() { foreground = false; retainedViews.forEach { $0.setForeground(false) } }
  func resume() { foreground = true; retainedViews.forEach { $0.setForeground(true) } }
  func closeAll() {
    let staged = Array(pendingWindows.values); pendingWindows.removeAll()
    staged.forEach { $0.view.release() }; retainedViews.forEach { $0.release() }
  }
  fileprivate func cancelWindows(openedBy opener: ProtectedWebView) {
    let tokens = pendingWindows.filter { $0.value.opener === opener }.map { $0.key }
    for token in tokens { pendingWindows.removeValue(forKey: token)?.view.release() }
    retainedViews.filter { $0.hasPendingWindow(openedBy: opener) }.forEach { $0.release() }
  }
  fileprivate func stageWindow(from opener: ProtectedWebView, configuration: WKWebViewConfiguration, target: URL) -> WKWebView? {
    guard mayOpen, foreground, pendingWindows.count < 4, let source = opener.renderer,
      configuration.websiteDataStore === source.configuration.websiteDataStore else { return nil }
    let child = ProtectedWebView(frame: .zero, id: nextPendingViewId, tabId: UUID().uuidString,
      privateMode: opener.privateMode, consumer: opener.consumer, restrictions: [:], bridge: self, inheriting: opener)
    nextPendingViewId -= 1
    guard let renderer = child.prepareWindow(configuration: configuration, target: target, opener: opener) else { return nil }
    let token = UUID().uuidString
    child.windowToken = token
    pendingWindows[token] = ConsumerPendingWindow(opener: opener, view: child)
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak child] in
      guard child?.windowToken == token else { return }
      self?.pendingWindows.removeValue(forKey: token)
      child?.release()
    }
    emit("newWindowRequested", ["viewId": opener.id, "requestId": opener.requestId, "url": target.absoluteString, "windowToken": token])
    return renderer
  }
  fileprivate func remove(_ id: Int64) { views.removeValue(forKey: id) }
  fileprivate var mayOpen: Bool { ready && !handoffBlocked && !cleanupPending && !updateRecoveryRequired && baseline.valid }
  fileprivate var isForeground: Bool { foreground }
  fileprivate var rules: [WKContentRuleList] { compiled }
  fileprivate func checked(_ raw: String) -> ConsumerNativeDecision { baseline.check(raw) }
  fileprivate func emit(_ event: String, _ data: [String: Any]) { channel.invokeMethod(event, arguments: data) }
  private func error(_ result: FlutterResult, _ reason: String = "The destination is blocked by the current protection policy.") {
    result(FlutterError(code: "protected_navigation_denied", message: reason, details: nil))
  }
  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if ["prepareConsumerPolicy", "activateConsumerPolicy", "discardConsumerPolicy", "revertConsumerPolicy"].contains(call.method) {
      handleUpdate(call.method, args, result); return
    }
    if call.method == "capabilities" {
      result(["supported": mayOpen, "privateAvailable": mayOpen, "strictSearchAvailable": mayOpen, "mode": "consumerWeb",
        "javascript": true, "forms": true, "cookies": true, "storage": true, "history": true, "uploads": true, "downloads": true,
        "findInPage": true, "media": true, "originPermissions": true, "policyUpdatesAvailable": !updateKeys.isEmpty, "defaultBrowserAvailable": BrowserNativeBridge.hasDefaultBrowserEntitlement,
        "reason": mayOpen ? NSNull() as Any : "Mandatory protection data is unavailable. Recovery is required." as Any]); return
    }
    if call.method == "state", args["viewId"] == nil {
      result(["views": retainedViews.filter { $0.hasRenderer }.count, "ready": ready, "foreground": foreground,
        "handoffBlocked": handoffBlocked, "cleanupPending": cleanupPending, "baselineValid": baseline.valid,
        "preparedRuleSets": compiled.count, "ruleCompilationCount": compilationCount, "domainCount": baseline.domainCount, "policyRecoveryRequired": updateRecoveryRequired, "policySHA256": activeDigest]); return
    }
    guard let id = (args["viewId"] as? NSNumber)?.int64Value, let view = views[id]?.value else { error(result); return }
    switch call.method {
    case "adoptWindow":
      guard let token = args["windowToken"] as? String, let request = (args["requestId"] as? NSNumber)?.int64Value,
        view.activateWindow(token: token, request: request) else { error(result, "The new window expired or its owning session changed."); return }
      result(nil)
    case "open", "openSearch":
      let raw = call.method == "openSearch" ? strictSearchURL(args["query"] as? String ?? "") : args["url"] as? String
      guard mayOpen, let raw = raw, let request = (args["requestId"] as? NSNumber)?.int64Value, request > view.requestId else { error(result); return }
      let decision = checked(raw)
      guard let target = decision.url else { error(result, decision.reason); return }
      view.open(target, request: request); result(nil)
    case "reload":
      if let request = (args["requestId"] as? NSNumber)?.int64Value { view.advanceRequest(request) }
      view.reload(); result(nil)
    case "back": view.back(); result(nil)
    case "forward": view.forward(); result(nil)
    case "stop": view.stop(); result(nil)
    case "setActive": view.setActive(args["active"] as? Bool == true); result(nil)
    case "find", "findNext": view.find(args["query"] as? String, forward: args["forward"] as? Bool != false, result: result)
    case "clearFind": view.find("", forward: true, result: result)
    case "share": view.share(); result(nil)
    case "updateRestrictions": view.updateRestrictions(args) { result(nil) }
    case "close": view.release(); views.removeValue(forKey: id); result(nil)
    case "state": result(view.state)
    default: result(FlutterError(code: "protected_method_unavailable", message: "This browser operation is unavailable.", details: nil))
    }
  }

  private func handleUpdate(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) {
    func reject(_ message: String) { result(FlutterError(code: "consumer_update_rejected", message: message, details: nil)) }
    let receiptURL = try? ConsumerNativeUpdate.directory().appendingPathComponent("receipt.json")
    let receipt: [String: Any]
    do { receipt = try ConsumerNativeUpdate.receipt() }
    catch { reject("The native policy receipt requires recovery."); return }
    let highWater = receipt["highest"] as? Int ?? 1
    switch method {
    case "prepareConsumerPolicy":
      guard !updateKeys.isEmpty else { reject("No consumer update signing key is provisioned."); return }
      guard pendingUpdate == nil, let envelope = (args["envelope"] as? FlutterStandardTypedData)?.data,
        let data = (args["data"] as? FlutterStandardTypedData)?.data else { reject("A bounded policy candidate is required."); return }
      do {
        let candidate = try ConsumerNativeUpdate(envelope: envelope, data: data, keys: updateKeys)
        let restore = args["restore"] as? Bool == true
        let knownActive = receipt["sequence"] as? Int == candidate.sequence && receipt["sha256"] as? String == candidate.digest
        let prior = receipt["previous"] as? [String: Any] ?? [:]
        let knownPrevious = prior["sequence"] as? Int == candidate.sequence && prior["sha256"] as? String == candidate.digest
        guard candidate.sequence > highWater || (restore && (knownActive || knownPrevious)) else { reject("The policy sequence is not eligible for activation."); return }
        pendingUpdate = candidate
        let groups = candidate.policy.contentRuleGroups()
        func compile(_ index: Int) {
          guard self.pendingUpdate === candidate else { reject("The staged policy was discarded."); return }
          guard index < groups.count else {
            candidate.prepared = true
            result(["ready": true, "token": candidate.token, "sequence": candidate.sequence, "sha256": candidate.digest]); return
          }
          let identifier = consumerContentRuleIdentifier(digest: candidate.digest, index: index, count: groups.count)
          WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { existing, _ in
            if let existing = existing { candidate.rules.append(existing); compile(index + 1); return }
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: groups[index]) { list, error in
              guard let list = list, error == nil else { self.pendingUpdate = nil; reject("The policy resource rules could not be prepared."); return }
              candidate.rules.append(list); compile(index + 1)
            }
          }
        }
        compile(0)
      } catch { reject("The consumer policy signature, metadata or data is invalid.") }
    case "activateConsumerPolicy":
      guard let candidate = pendingUpdate, args["token"] as? String == candidate.token,
        candidate.prepared, !candidate.rules.isEmpty else { reject("A prepared native policy token is required."); return }
      // Save the candidate, then atomically replace the small receipt before
      // making policy visible. Dart records its own commit after this receipt.
      do {
        try candidate.persist()
        let oldReceipt: [String: Any] = receipt.isEmpty ? ["sequence": 1, "sha256": Self.protectionSHA256] : receipt
        let newReceipt = consumerActivationReceipt(currentSequence: oldReceipt["sequence"] as? Int ?? 1,
          currentDigest: oldReceipt["sha256"] as? String ?? Self.protectionSHA256, previous: oldReceipt["previous"] as? [String: Any],
          sequence: candidate.sequence, digest: candidate.digest, highWater: highWater)
        guard let receiptURL = receiptURL else { throw ConsumerNativeUpdateError.invalid }
        try JSONSerialization.data(withJSONObject: newReceipt).write(to: receiptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        closeAll()
        revertUpdate = (candidate.token, baseline, compiled, oldReceipt, updateRecoveryRequired)
        baseline = candidate.policy; compiled = candidate.rules; activeDigest = candidate.digest; ready = true; updateRecoveryRequired = false
        pendingUpdate = nil
        ConsumerNativeUpdate.prune(receipts: [newReceipt, oldReceipt])
        result(["activated": true, "sequence": candidate.sequence, "sha256": candidate.digest])
      } catch { reject("The verified policy could not be saved locally.") }
    case "discardConsumerPolicy":
      guard let candidate = pendingUpdate, args["token"] as? String == candidate.token else { reject("Unknown staged policy token."); return }
      pendingUpdate = nil; result(["discarded": true])
    case "revertConsumerPolicy":
      if let prepared = pendingUpdate, args["token"] as? String == prepared.token {
        pendingUpdate = nil; result(["reverted": true]); return
      }
      guard let previous = revertUpdate, args["token"] as? String == previous.token else { reject("No reversible activation matches this token."); return }
      var restored = previous.receipt; restored["highest"] = max(highWater, restored["highest"] as? Int ?? 1)
      do {
        guard let receiptURL = receiptURL else { throw ConsumerNativeUpdateError.invalid }
        try JSONSerialization.data(withJSONObject: restored).write(to: receiptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch { reject("The native rollback receipt could not be saved."); return }
      closeAll(); baseline = previous.policy; compiled = previous.rules; ready = true; updateRecoveryRequired = previous.recoveryRequired
      activeDigest = restored["sha256"] as? String ?? Self.protectionSHA256
      revertUpdate = nil; ConsumerNativeUpdate.prune(receipts: [restored]); result(["reverted": true])
    default: reject("Unsupported consumer policy operation.")
    }
  }
}

private final class WeakProtectedWebView {
  weak var value: ProtectedWebView?
  init(_ value: ProtectedWebView) { self.value = value }
}

private final class ConsumerPendingWindow {
  weak var opener: ProtectedWebView?
  let view: ProtectedWebView
  init(opener: ProtectedWebView, view: ProtectedWebView) {
    self.opener = opener; self.view = view
  }
  var isCurrent: Bool { view.windowOwnerIsCurrent }
}

/// Both factory claim and activation use the same immutable ownership lease.
/// Renderer identity alone does not survive navigation to a different document.
struct ConsumerWindowOwnerSnapshot {
  let renderer: ObjectIdentifier
  let generation: Int
  let origin: String?
  let restrictionVersion: Int
  let expiresAt: Date
  func matches(renderer candidate: AnyObject?, generation: Int, origin: String?, restrictionVersion: Int, now: Date = Date()) -> Bool {
    guard let candidate = candidate else { return false }
    return now < expiresAt && renderer == ObjectIdentifier(candidate) && self.generation == generation &&
      self.origin == origin && self.restrictionVersion == restrictionVersion
  }
}

final class ConsumerReply<Value> {
  private var callback: ((Value) -> Void)?
  init(_ callback: @escaping (Value) -> Void) { self.callback = callback }
  func resolve(_ value: Value) { let callback = self.callback; self.callback = nil; callback?(value) }
}

/// UIKit can return an older export picker while a new upload is pending.
/// A callback may consume only the reply owned by its original picker.
final class ConsumerOwnedReply<Value> {
  private weak var owner: AnyObject?
  private let reply: ConsumerReply<Value>
  init(owner: AnyObject, callback: @escaping (Value) -> Void) {
    self.owner = owner; reply = ConsumerReply(callback)
  }
  func belongs(to candidate: AnyObject) -> Bool { owner === candidate }
  func resolve(from candidate: AnyObject, value: Value) {
    guard belongs(to: candidate) else { return }; reply.resolve(value)
  }
  func cancel(_ value: Value) { reply.resolve(value) }
}

private final class ConsumerPresentation {
  weak var controller: UIViewController?
  let cancel: () -> Void
  init(_ controller: UIViewController, cancel: @escaping () -> Void) { self.controller = controller; self.cancel = cancel }
}

private final class ProtectedWebView: NSObject, FlutterPlatformView, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, UIDocumentPickerDelegate {
  private(set) var id: Int64
  private(set) var tabId: String
  let privateMode: Bool
  let consumer: Bool
  weak var bridge: ProtectedWebBridge?
  private let container: UIView
  private var web: WKWebView?
  private var observations: [NSKeyValueObservation] = []
  private(set) var currentURL = ""
  private var committedURL = ""
  private var policyCancellationUntil = Date.distantPast
  private(set) var requestId: Int64 = 0
  private var active = true
  private var foreground = true
  private var errorText: String?
  private var findQuery = ""
  private var uploadReply: ConsumerOwnedReply<[URL]?>?
  private var downloads: [ObjectIdentifier: (WKDownload, URL?)] = [:]
  private var downloadGestureUntil = Date.distantPast
  private var blockedDomains = Set<String>()
  private var blockedSearch = false
  private var blockedURLs = Set<String>()
  private var documentGeneration = 0
  private var uploadGeneration = -1
  private weak var uploadRenderer: WKWebView?
  private var uploadOrigin: String?
  private var lastNewWindow: (String, Date)?
  private var additionalRules: WKContentRuleList?
  private var restrictionVersion = 0
  private var restrictionsReady = true
  private var restrictionFailure = false
  private var exportedTemporary: [ObjectIdentifier: URL] = [:]
  private var presentations: [ConsumerPresentation] = []
  fileprivate var windowToken: String?
  private var scriptWindow = false
  private var awaitingWindowAdoption = false
  private weak var windowOpener: ProtectedWebView?
  private weak var openerRenderer: WKWebView?
  private var windowOwner: ConsumerWindowOwnerSnapshot?
  private var deferredWindowNavigations: [(resume: () -> Void, cancel: () -> Void)] = []
  fileprivate var renderer: WKWebView? { web }
  var hasRenderer: Bool { web != nil }
  var state: [String: Any] {
    ["viewId": id, "requestId": requestId, "url": currentURL, "title": web?.title ?? "", "progress": Int((web?.estimatedProgress ?? 0) * 100),
     "isLoading": web?.isLoading ?? false, "error": errorText ?? NSNull() as Any, "canGoBack": web?.canGoBack ?? false,
     "canGoForward": web?.canGoForward ?? false, "blockedResources": NSNull(), "loadedResources": NSNull(), "bytesReceived": NSNull(),
     "hasRenderer": hasRenderer, "private": privateMode, "javascript": true, "resourceRulesInstalled": hasRenderer,
     "strictSearch": URL(string: currentURL)?.host == "safe.duckduckgo.com"]
  }
  init(frame: CGRect, id: Int64, tabId: String, privateMode: Bool, consumer: Bool, restrictions: [String: Any], bridge: ProtectedWebBridge, inheriting opener: ProtectedWebView? = nil) {
    self.id = id; self.tabId = tabId; self.privateMode = privateMode; self.consumer = consumer; self.bridge = bridge
    foreground = bridge.isForeground
    container = UIView(frame: frame); container.backgroundColor = .systemBackground
    super.init()
    if let opener = opener {
      blockedDomains = opener.blockedDomains; blockedURLs = opener.blockedURLs; blockedSearch = opener.blockedSearch
      additionalRules = opener.additionalRules; restrictionsReady = opener.restrictionsReady; restrictionFailure = opener.restrictionFailure
      active = false; awaitingWindowAdoption = true; scriptWindow = true
    } else { updateRestrictions(restrictions) {} }
  }
  func view() -> UIView { container }
  fileprivate func matchesRestrictions(_ values: [String: Any]) -> Bool {
    let domains = Set((values["blockedDomains"] as? [String] ?? []).compactMap { NativeGuardPolicy.normalizeHost($0) }.prefix(1000))
    let urls = Set((values["blockedUrls"] as? [String] ?? []).compactMap { consumerCheckedURL($0)?.absoluteString.components(separatedBy: "#")[0] }.prefix(5000))
    let search = (values["blockedCollections"] as? [String] ?? []).contains("web-search") || (values["blockedResourceIds"] as? [String] ?? []).contains("web-search")
    return domains == blockedDomains && urls == blockedURLs && search == blockedSearch
  }
  fileprivate func prepareWindow(configuration: WKWebViewConfiguration, target: URL, opener: ProtectedWebView) -> WKWebView? {
    guard restrictionsReady, !restrictionFailure, checked(target.absoluteString).url == target, let source = opener.web else { return nil }
    windowOpener = opener; openerRenderer = source; currentURL = target.absoluteString
    windowOwner = ConsumerWindowOwnerSnapshot(renderer: ObjectIdentifier(source), generation: opener.documentGeneration,
      origin: consumerOrigin(opener.currentURL), restrictionVersion: opener.restrictionVersion, expiresAt: Date().addingTimeInterval(10))
    return ensureRenderer(configuration: configuration)
  }
  fileprivate var windowOwnerIsCurrent: Bool {
    guard let opener = windowOpener, let owner = windowOwner, openerRenderer != nil else { return false }
    return owner.matches(renderer: opener.web, generation: opener.documentGeneration,
      origin: consumerOrigin(opener.currentURL), restrictionVersion: opener.restrictionVersion)
  }
  fileprivate func hasPendingWindow(openedBy opener: ProtectedWebView) -> Bool { awaitingWindowAdoption && windowOpener === opener }
  fileprivate func adoptIdentity(viewId: Int64, tabId: String, frame: CGRect) {
    id = viewId; self.tabId = tabId; container.frame = frame; web?.frame = container.bounds
  }
  fileprivate func activateWindow(token: String, request: Int64) -> Bool {
    guard windowToken == token, awaitingWindowAdoption, request > requestId,
      bridge?.mayOpen == true, foreground, restrictionsReady, !restrictionFailure,
      windowOwnerIsCurrent, checked(currentURL).url != nil else { return false }
    requestId = request; windowToken = nil; awaitingWindowAdoption = false; active = true
    if let web = web { consumerSetWebActivity(web, allowed: true) }
    let deferred = deferredWindowNavigations; deferredWindowNavigations.removeAll()
    deferred.forEach { $0.resume() }; emit(); return true
  }
  private func checked(_ raw: String) -> ConsumerNativeDecision {
    guard let decision = bridge?.checked(raw), let url = decision.url, let host = url.host else { return bridge?.checked(raw) ?? ConsumerNativeDecision() }
    if blockedURLs.contains(url.absoluteString.components(separatedBy: "#")[0]) || blockedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) || (blockedSearch && host == "safe.duckduckgo.com") {
      return ConsumerNativeDecision(nil, "This destination is blocked by an additional restriction.")
    }
    return decision
  }
  func updateRestrictions(_ values: [String: Any], completion: @escaping () -> Void) {
    let next = Set((values["blockedDomains"] as? [String] ?? []).compactMap { NativeGuardPolicy.normalizeHost($0) }.prefix(1000))
    let urls = Set((values["blockedUrls"] as? [String] ?? []).compactMap { consumerCheckedURL($0)?.absoluteString.components(separatedBy: "#")[0] }.prefix(5000))
    let search = (values["blockedCollections"] as? [String] ?? []).contains("web-search") || (values["blockedResourceIds"] as? [String] ?? []).contains("web-search")
    guard next != blockedDomains || search != blockedSearch || urls != blockedURLs else { completion(); return }
    blockedDomains = next; blockedSearch = search; blockedURLs = urls; restrictionVersion += 1
    let version = restrictionVersion
    restrictionsReady = false; restrictionFailure = false
    let restoreURL = web == nil ? nil : checked(currentURL).url
    // Adding a restriction closes the old renderer before new resource rules
    // compile. A live script cannot race the newly tightened policy.
    release()
    var hosts = Array(next)
    if search { hosts += ["safe.duckduckgo.com", "duckduckgo.com"] }
    if hosts.isEmpty && urls.isEmpty {
      if let list = additionalRules { web?.configuration.userContentController.remove(list) }
      additionalRules = nil; restrictionsReady = true; if let restoreURL = restoreURL { open(restoreURL, request: requestId) }; completion(); return
    }
    var rules = hosts.map { host in
      ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: host) + "\\.?[/:]"], "action": ["type": "block"]] as [String: Any]
    }
    rules += urls.map { url in
      ["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: url) + "$"], "action": ["type": "block"]] as [String: Any]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { release(); restrictionFailure = true; restrictionsReady = true; completion(); return }
    let identifier = "wingman-additional-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { [weak self] list, error in
      guard let self = self, version == self.restrictionVersion else { completion(); return }
      guard let list = list, error == nil else { self.release(); self.restrictionFailure = true; self.restrictionsReady = true; completion(); return }
      if let old = self.additionalRules { self.web?.configuration.userContentController.remove(old) }
      self.additionalRules = list; self.web?.configuration.userContentController.add(list); self.restrictionsReady = true; if let restoreURL = restoreURL { self.open(restoreURL, request: self.requestId) }; completion()
    }
  }

  deinit { release(); bridge?.remove(id) }
  private func emit() { bridge?.emit("pageState", state) }
  func advanceRequest(_ value: Int64) { requestId = max(requestId, value) }
  private func ensureRenderer(configuration suppliedConfiguration: WKWebViewConfiguration? = nil) -> WKWebView? {
    if let web = web { return web }
    guard consumer, bridge?.mayOpen == true, !tabId.isEmpty, tabId.count <= 100 else { return nil }
    let configuration = suppliedConfiguration ?? consumerWebConfiguration(privateMode: privateMode, rules: bridge?.rules ?? [])
    if suppliedConfiguration != nil {
      // Preserve WebKit's opener/process/store configuration, but install only
      // our own trusted resource rules and never a page message handler.
      configuration.userContentController = WKUserContentController()
      for rule in bridge?.rules ?? [] { configuration.userContentController.add(rule) }
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
      configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    }
    if let additionalRules = additionalRules { configuration.userContentController.add(additionalRules) }
    let renderer = WKWebView(frame: container.bounds, configuration: configuration)
    renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    renderer.navigationDelegate = self; renderer.uiDelegate = self
    renderer.allowsLinkPreview = false // Preview can navigate outside our tab delegate.
    renderer.allowsBackForwardNavigationGestures = true
    if #available(iOS 16.4, *) { renderer.isInspectable = false }
    web = renderer
    consumerSetWebActivity(renderer, allowed: active && foreground)
    observations = [
      renderer.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.title, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.emit() },
    ]
    container.addSubview(renderer)
    return renderer
  }
  func open(_ url: URL, request: Int64) {
    requestId = request; errorText = nil
    if !restrictionsReady {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self = self, self.requestId == request else { return }; self.open(url, request: request)
      }
      return
    }
    guard !restrictionFailure, checked(url.absoluteString).url != nil else { blocked(url.absoluteString, "Additional restriction."); return }
    guard let renderer = ensureRenderer() else { errorText = "Consumer browsing is unavailable in this edition."; emit(); return }
    currentURL = url.absoluteString
    var request = URLRequest(url: url)
    request.setValue("1", forHTTPHeaderField: "DNT"); request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    renderer.load(request); emit()
  }
  func setActive(_ value: Bool) { active = value; if let web = web { consumerSetWebActivity(web, allowed: active && foreground) }; emit() }
  func setForeground(_ value: Bool) { foreground = value; if let web = web { consumerSetWebActivity(web, allowed: active && foreground) } }
  func back() { errorText = nil; web?.goBack() }
  func forward() { errorText = nil; web?.goForward() }
  func reload() {
    errorText = nil
    if let url = checked(currentURL).url {
      if let web = web { web.reload() } else { open(url, request: requestId) }
    }
    emit()
  }
  func stop() { web?.stopLoading(); emit() }
  func release() {
    bridge?.cancelWindows(openedBy: self)
    windowToken = nil; awaitingWindowAdoption = false
    let deferred = deferredWindowNavigations; deferredWindowNavigations.removeAll(); deferred.forEach { $0.cancel() }
    committedURL = ""; policyCancellationUntil = .distantPast
    uploadReply?.cancel(nil); uploadReply = nil; uploadRenderer = nil; uploadOrigin = nil
    let owned = presentations; presentations.removeAll()
    for presentation in owned { presentation.cancel(); presentation.controller?.dismiss(animated: false) }
    for url in exportedTemporary.values { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    exportedTemporary.removeAll()
    for (_, entry) in downloads { entry.0.delegate = nil; entry.0.cancel { _ in }; if let url = entry.1 { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
    downloads.removeAll(); observations.forEach { $0.invalidate() }; observations.removeAll()
    if let web = web { consumerSetWebActivity(web, allowed: false) }
    web?.stopLoading(); web?.navigationDelegate = nil; web?.uiDelegate = nil; web?.removeFromSuperview(); web = nil
  }
  private func blocked(_ raw: String, _ reason: String) {
    policyCancellationUntil = Date().addingTimeInterval(15)
    errorText = nil
    if !committedURL.isEmpty { currentURL = committedURL }
    emit()
    bridge?.emit("navigationBlocked", ["viewId": id, "requestId": requestId, "url": raw, "reason": reason])
  }
  func find(_ query: String?, forward: Bool, result: @escaping FlutterResult) {
    if let query = query { findQuery = String(query.prefix(512)) }
    guard let web = web else { result(false); return }
    let configuration = WKFindConfiguration(); configuration.backwards = !forward; configuration.wraps = true
    web.find(findQuery, configuration: configuration) { result($0.matchFound) }
  }
  private var presenter: UIViewController? {
    var controller = container.window?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
  private func presentOwned(_ controller: UIViewController, from presenter: UIViewController, cancel: @escaping () -> Void = {}) {
    presentations = presentations.filter { $0.controller != nil }
    presentations.append(ConsumerPresentation(controller, cancel: cancel))
    presenter.present(controller, animated: true)
  }
  func share() {
    guard active, foreground, let url = checked(currentURL).url, let presenter = presenter else { return }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = container; sheet.popoverPresentationController?.sourceRect = container.bounds
    presentOwned(sheet, from: presenter)
  }
  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard webView === web, bridge?.mayOpen == true, let raw = action.request.url?.absoluteString else { decisionHandler(.cancel); return }
    if awaitingWindowAdoption {
      guard deferredWindowNavigations.count < 8 else { decisionHandler(.cancel); return }
      let reply = ConsumerReply(decisionHandler)
      deferredWindowNavigations.append((resume: { [weak self, weak webView] in
        guard let self = self, let webView = webView else { reply.resolve(.cancel); return }
        self.webView(webView, decidePolicyFor: action, decisionHandler: { reply.resolve($0) })
      }, cancel: { reply.resolve(.cancel) }))
      return
    }
    // Embedded blank/blob documents retain WebKit origin inheritance. Never
    // load a file:, data:, javascript: or arbitrary external scheme as a page.
    if action.targetFrame?.isMainFrame == false && (raw == "about:blank" || raw.hasPrefix("blob:")) { decisionHandler(.allow); return }
    let decision = checked(raw)
    guard let target = decision.url else { decisionHandler(.cancel); if action.targetFrame?.isMainFrame != false { blocked(raw, decision.reason) }; return }
    let userInitiated = action.navigationType == .linkActivated || action.navigationType == .formSubmitted || action.navigationType == .formResubmitted
    if userInitiated { downloadGestureUntil = Date().addingTimeInterval(15) }
    if action.targetFrame == nil {
      guard active, foreground else { decisionHandler(.cancel); return }
      if target.absoluteString != raw {
        policyCancellationUntil = Date().addingTimeInterval(15); decisionHandler(.cancel)
        if userInitiated { requestWindow(target) }
      } else { decisionHandler(.allow) }
      return
    }
    let safeProviderPost = action.request.httpMethod == "POST" && action.request.url?.scheme == "https" && action.request.url?.host == "safe.duckduckgo.com" &&
      ["/html/", "/lite/", "/html", "/lite", "/"].contains(URLComponents(string: raw)?.path ?? "") && target.host == "safe.duckduckgo.com"
    if target.absoluteString != raw && !safeProviderPost {
      policyCancellationUntil = Date().addingTimeInterval(15)
      decisionHandler(.cancel)
      // Rewrites never forward POST bodies, Authorization, Referer or cookies
      // from a wrapper/provider endpoint to the rewritten destination.
      guard action.targetFrame?.isMainFrame == true else { return }
      currentURL = target.absoluteString; webView.load(URLRequest(url: target)); return
    }
    if action.shouldPerformDownload {
      guard active, foreground, userInitiated else { decisionHandler(.cancel); return }
      policyCancellationUntil = Date().addingTimeInterval(15)
      decisionHandler(.download); return
    }
    if action.targetFrame?.isMainFrame == true {
      bridge?.cancelWindows(openedBy: self)
      documentGeneration += 1; currentURL = target.absoluteString; errorText = nil
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    guard let raw = webView.url?.absoluteString else { return }
    let decision = checked(raw)
    if decision.url == nil { webView.stopLoading(); blocked(raw, decision.reason) }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    guard webView === web, bridge?.mayOpen == true, let raw = response.response.url?.absoluteString, checked(raw).url != nil else { decisionHandler(.cancel); return }
    let attachment = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().contains("attachment") == true
    if !response.canShowMIMEType || attachment {
      let allowed = active && foreground && Date() < downloadGestureUntil
      policyCancellationUntil = Date().addingTimeInterval(15)
      decisionHandler(allowed ? .download : .cancel)
      if !allowed { blocked(raw, "Open a download link to save this file.") }
      return
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { if webView === web { currentURL = webView.url?.absoluteString ?? currentURL; committedURL = currentURL; emit() } }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if webView === web { currentURL = webView.url?.absoluteString ?? currentURL; committedURL = currentURL; errorText = nil; emit() } }
  private func failed(_ error: Error) {
    if consumerExpectedNavigationCancellation(error as NSError, policyCancellationExpected: Date() < policyCancellationUntil) { return }
    // Deliberately avoid URLs and provider/query contents in logs and errors.
    errorText = (error as NSError).domain == NSURLErrorDomain && (-1206 ... -1200).contains((error as NSError).code)
      ? "The secure connection could not be verified. Wingman did not bypass it." : "This page could not load. Check the connection or try again."
    emit()
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === web { failed(error) } }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === web { failed(error) } }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === web { release(); bridge?.emit("rendererGone", ["viewId": id, "requestId": requestId]) } }
  func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // Never accept a supplied certificate exception. OS/WebKit decide trust.
    completionHandler(.performDefaultHandling, nil)
  }
  private func requestWindow(_ target: URL) {
    if let last = lastNewWindow, last.0 == target.absoluteString, Date().timeIntervalSince(last.1) < 0.5 { return }
    lastNewWindow = (target.absoluteString, Date())
    bridge?.emit("newWindowRequested", ["viewId": id, "requestId": requestId, "url": target.absoluteString])
  }
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    // WebKit calls this for script windows only after its user-gesture gate:
    // javaScriptCanOpenWindowsAutomatically remains false on every renderer.
    guard webView === web, active, foreground, let raw = action.request.url?.absoluteString else { return nil }
    let decision = checked(raw)
    guard let target = decision.url else { blocked(raw, decision.reason); return nil }
    guard target.absoluteString == raw, ["GET", "POST"].contains(action.request.httpMethod ?? "GET") else { return nil }
    return bridge?.stageWindow(from: self, configuration: configuration, target: target)
  }
  func webViewDidClose(_ webView: WKWebView) {
    guard webView === web, scriptWindow else { return }
    release(); bridge?.emit("closeRequested", ["viewId": id, "requestId": requestId])
  }
  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    guard webView === web, active, foreground, let presenter = presenter else { completionHandler(); return }
    let reply = ConsumerReply<Void> { _ in completionHandler() }
    let alert = UIAlertController(title: frame.securityOrigin.host, message: String(message.prefix(2000)), preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply.resolve(()) })
    presentOwned(alert, from: presenter, cancel: { reply.resolve(()) })
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    guard webView === web, active, foreground, let presenter = presenter else { completionHandler(false); return }
    let reply = ConsumerReply(completionHandler)
    let alert = UIAlertController(title: frame.securityOrigin.host, message: String(message.prefix(2000)), preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply.resolve(false) })
    alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply.resolve(true) })
    presentOwned(alert, from: presenter, cancel: { reply.resolve(false) })
  }
  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    guard webView === web, active, foreground, let presenter = presenter else { completionHandler(nil); return }
    let reply = ConsumerReply(completionHandler)
    let alert = UIAlertController(title: frame.securityOrigin.host, message: String(prompt.prefix(2000)), preferredStyle: .alert)
    alert.addTextField { $0.text = String((defaultText ?? "").prefix(2000)) }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply.resolve(nil) })
    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in reply.resolve(alert?.textFields?.first?.text) })
    presentOwned(alert, from: presenter, cancel: { reply.resolve(nil) })
  }
  @available(iOS 18.4, *)
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    guard webView === web, bridge?.mayOpen == true, active, foreground, uploadReply == nil, let raw = frame.request.url?.absoluteString, checked(raw).url != nil, let presenter = presenter else { completionHandler(nil); return }
    guard frame.isMainFrame, let origin = consumerOrigin(raw), origin == consumerOrigin(currentURL) else { completionHandler(nil); return }
    uploadGeneration = documentGeneration; uploadRenderer = web; uploadOrigin = origin
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: parameters.allowsDirectories ? [.folder, .item] : [.item], asCopy: true)
    uploadReply = ConsumerOwnedReply(owner: picker, callback: completionHandler)
    picker.allowsMultipleSelection = parameters.allowsMultipleSelection; picker.delegate = self
    presentOwned(picker, from: presenter)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let reply = uploadReply, reply.belongs(to: controller) {
      uploadReply = nil
      let valid = active && foreground && bridge?.mayOpen == true && uploadRenderer === web && uploadGeneration == documentGeneration && uploadOrigin == consumerOrigin(currentURL) && checked(currentURL).url != nil
      uploadRenderer = nil; uploadOrigin = nil
      reply.resolve(from: controller, value: valid ? urls : nil)
    }
    cleanExport(for: controller)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let reply = uploadReply, reply.belongs(to: controller) {
      uploadReply = nil; uploadRenderer = nil; uploadOrigin = nil; reply.resolve(from: controller, value: nil)
    }
    cleanExport(for: controller)
  }
  private func cleanExport(for controller: UIDocumentPickerViewController) {
    if let url = exportedTemporary.removeValue(forKey: ObjectIdentifier(controller)) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  }
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    guard webView === web, bridge?.mayOpen == true, active, foreground, origin.protocol == "https", let frameURL = frame.request.url, frameURL.host == origin.host,
      checked(frameURL.absoluteString).url != nil else { decisionHandler(.deny); return }
    decisionHandler(.prompt) // WebKit's origin-scoped prompt plus OS permission.
  }
  private func ownsDownload(_ download: WKDownload) -> Bool {
    web != nil && bridge?.mayOpen == true && !awaitingWindowAdoption && downloads[ObjectIdentifier(download)]?.0 === download
  }
  private func acceptDownload(_ download: WKDownload, from source: WKWebView) {
    guard source === web, bridge?.mayOpen == true, active, foreground, !awaitingWindowAdoption else {
      download.delegate = nil; download.cancel { _ in }; return
    }
    downloads[ObjectIdentifier(download)] = (download, nil); download.delegate = self
  }
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { acceptDownload(download, from: webView) }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { acceptDownload(download, from: webView) }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    guard ownsDownload(download), active, foreground, let url = response.url, checked(url.absoluteString).url != nil, let presenter = presenter else { completionHandler(nil); return }
    let reply = ConsumerReply(completionHandler)
    let filename = String(URL(fileURLWithPath: suggestedFilename).lastPathComponent.prefix(180))
    let safeName = filename.isEmpty || filename == "." || filename == ".." ? "download" : filename
    let alert = UIAlertController(title: "Download file?", message: "\(safeName)\nFrom \(url.host ?? "this website")", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply.resolve(nil) })
    alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
      guard self.ownsDownload(download), self.active, self.foreground, self.checked(url.absoluteString).url != nil else { reply.resolve(nil); return }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WingmanDownload-" + UUID().uuidString, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(safeName)
        self.downloads[ObjectIdentifier(download)] = (download, destination); reply.resolve(destination)
      } catch { reply.resolve(nil) }
    }); presentOwned(alert, from: presenter, cancel: { reply.resolve(nil) })
  }
  func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
    guard ownsDownload(download), let raw = request.url?.absoluteString, let target = checked(raw).url, target.absoluteString == raw else { decisionHandler(.cancel); return }
    decisionHandler(.allow)
  }
  func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(ownsDownload(download) ? .performDefaultHandling : .cancelAuthenticationChallenge, nil) }
  func downloadDidFinish(_ download: WKDownload) {
    let current = ownsDownload(download)
    guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)), let url = entry.1 else { return }
    download.delegate = nil
    guard current, let presenter = presenter, active, foreground else { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    exportedTemporary[ObjectIdentifier(picker)] = url
    picker.delegate = self
    presentOwned(picker, from: presenter)
    // Exported files are user-owned; remove the temporary source after the
    // picker completes or cancels, and at next launch after a process crash.
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    let current = ownsDownload(download)
    guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    download.delegate = nil
    if let url = entry.1 { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    guard current else { return }
    bridge?.emit("downloadFailed", ["viewId": id, "requestId": requestId, "reason": "The download could not finish."])
  }
}

/// Playback suspension alone does not stop microphone/camera capture. Hidden
/// tabs and inactive scenes must end capture and dismiss fullscreen/PiP too.
/// Returning to the tab resumes playback eligibility, never a capture grant.
func consumerSetWebActivity(_ web: WKWebView, allowed: Bool) {
  web.setAllMediaPlaybackSuspended(!allowed)
  if !allowed {
    web.setCameraCaptureState(.none, completionHandler: nil)
    web.setMicrophoneCaptureState(.none, completionHandler: nil)
    web.closeAllMediaPresentations(completionHandler: nil)
  }
}

/// A deliberate WebKit policy cancellation is not a network/TLS failure.
func consumerExpectedNavigationCancellation(_ error: NSError, policyCancellationExpected: Bool) -> Bool {
  (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) ||
    (policyCancellationExpected && error.domain == "WebKitErrorDomain" && error.code == 102)
}

func consumerWebConfiguration(privateMode: Bool, rules: [WKContentRuleList]) -> WKWebViewConfiguration {
  let configuration = WKWebViewConfiguration()
  configuration.websiteDataStore = privateMode ? .nonPersistent() : .default()
  configuration.defaultWebpagePreferences.allowsContentJavaScript = true
  configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
  configuration.preferences.isFraudulentWebsiteWarningEnabled = true
  if #available(iOS 15.4, *) { configuration.preferences.isElementFullscreenEnabled = true }
  configuration.allowsInlineMediaPlayback = true
  configuration.mediaTypesRequiringUserActionForPlayback = .all
  for rule in rules { configuration.userContentController.add(rule) }
  return configuration
}

private func consumerOrigin(_ raw: String) -> String? {
  guard let components = URLComponents(string: raw), let scheme = components.scheme, let host = components.host else { return nil }
  return "\(scheme.lowercased())://\(host.lowercased()):\(components.port ?? (scheme == "https" ? 443 : 80))"
}

private func consumerBaselineDomain(_ host: String) -> Bool {
  let bytes = host.utf8
  guard !bytes.isEmpty, bytes.count <= 253,
    bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else { return false }
  return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
    !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
  }
}

/// Restoring the acknowledged active release must not erase its predecessor.
func consumerActivationReceipt(currentSequence: Int, currentDigest: String, previous: [String: Any]?, sequence: Int, digest: String, highWater: Int) -> [String: Any] {
  let restoringCurrent = currentSequence == sequence && currentDigest == digest
  let prior = restoringCurrent ? previous : nil
  return ["sequence": sequence, "sha256": digest, "highest": max(highWater, sequence),
    "previous": prior ?? ["sequence": currentSequence, "sha256": currentDigest]]
}

enum ConsumerNativeUpdateError: Error { case invalid }

/// Update trust roots are shipped only in the signed application bundle. The
/// production asset intentionally has no keys until a real feed is provisioned.
final class ConsumerNativeUpdate {
  let token = UUID().uuidString
  let sequence: Int
  let digest: String
  let policy: ConsumerNativePolicy
  let envelope: Data
  let data: Data
  var rules: [WKContentRuleList] = []
  var prepared = false
  init(envelope: Data, data: Data, keys: [String: String]) throws {
    guard envelope.count <= 64 * 1024, !data.isEmpty, data.count <= 16 * 1024 * 1024,
      let outer = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any], outer.count == 3,
      let keyID = outer["keyId"] as? String, let encodedKey = keys[keyID], let keyData = Data(base64Encoded: encodedKey), keyData.count == 32,
      let encodedPayload = outer["payload"] as? String, let payload = Data(base64Encoded: encodedPayload),
      let encodedSignature = outer["signature"] as? String, let signature = Data(base64Encoded: encodedSignature), signature.count == 64,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), key.isValidSignature(signature, for: payload),
      let meta = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
      meta["purpose"] as? String == "wingman-consumer-protection-v1", meta["schemaVersion"] as? Int == 1,
      let sequence = meta["sequence"] as? Int, (2...2147483647).contains(sequence),
      let version = meta["version"] as? String, version.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,79}$", options: .regularExpression) != nil,
      let generated = meta["generatedAt"] as? String, generated.hasSuffix("Z"), let generatedDate = consumerISODate(generated), generatedDate <= Date().addingTimeInterval(86400),
      let minimum = meta["minimumAppVersion"] as? String,
      consumerAppVersionSupported(minimum), meta["filename"] as? String == "consumer-\(sequence).json",
      meta["bytes"] as? Int == data.count, let digest = meta["sha256"] as? String,
      digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest,
      let license = meta["license"] as? String, !license.isEmpty, license.count <= 4096,
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], body["sequence"] as? Int == sequence,
      body["version"] as? String == version, body["generatedAt"] as? String == generated else { throw ConsumerNativeUpdateError.invalid }
    let policy = ConsumerNativePolicy(data: data, expectedDigest: digest)
    guard policy.valid else { throw ConsumerNativeUpdateError.invalid }
    self.sequence = sequence; self.digest = digest; self.policy = policy; self.envelope = envelope; self.data = data
  }
  static func directory() throws -> URL {
    var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wingman/ConsumerPolicies", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
    return directory
  }
  static func receipt() throws -> [String: Any] {
    let url = try directory().appendingPathComponent("receipt.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let bytes = try Data(contentsOf: url)
    guard bytes.count <= 16384, let receipt = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
      let sequence = receipt["sequence"] as? Int, (1...2147483647).contains(sequence),
      let highest = receipt["highest"] as? Int, highest >= sequence, highest <= 2147483647,
      let digest = receipt["sha256"] as? String, digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ConsumerNativeUpdateError.invalid }
    if let previous = receipt["previous"] as? [String: Any] {
      guard let priorSequence = previous["sequence"] as? Int, (1...highest).contains(priorSequence),
        let priorDigest = previous["sha256"] as? String, priorDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ConsumerNativeUpdateError.invalid }
    }
    return receipt
  }
  static func prune(receipts: [[String: Any]]) {
    var retained = Set<String>()
    for receipt in receipts {
      if let digest = receipt["sha256"] as? String { retained.insert(digest) }
      if let prior = receipt["previous"] as? [String: Any], let digest = prior["sha256"] as? String { retained.insert(digest) }
    }
    guard let directory = try? directory(), let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
    for file in files where file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.json$", options: .regularExpression) != nil && !retained.contains(file.deletingPathExtension().lastPathComponent) {
      try? FileManager.default.removeItem(at: file)
    }
  }
  func persist() throws {
    let package: [String: Any] = ["envelope": envelope.base64EncodedString(), "data": data.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: package).write(to: Self.directory().appendingPathComponent(digest + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

private func consumerISODate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  if let date = formatter.date(from: value) { return date }
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value)
}

private func consumerAppVersionSupported(_ minimum: String) -> Bool {
  let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.10.0"
  func parts(_ value: String) -> [Int]? {
    guard value.range(of: "^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$", options: .regularExpression) != nil else { return nil }
    let values = value.split(separator: ".", omittingEmptySubsequences: false)
    guard values.count == 3 else { return nil }
    let parsed = values.compactMap { Int($0) }
    return parsed.count == 3 && parsed.allSatisfy { $0 >= 0 } ? parsed : nil
  }
  guard let required = parts(minimum), let actual = parts(current) else { return false }
  for i in 0..<3 { if actual[i] != required[i] { return actual[i] > required[i] } }
  return true
}

struct ConsumerNativeDecision {
  let url: URL?
  let reason: String
  init(_ url: URL? = nil, _ reason: String = "This destination is blocked by Wingman's protection policy.") { self.url = url; self.reason = reason }
}

/// Pinned baseline or independently verified signed update. Classification is
/// local; no browsing URLs are sent to a policy service.
final class ConsumerNativePolicy {
  private(set) var valid = false
  private var domains: [String: String] = [:]
  private var pathRules: [(host: String, path: String, category: String)] = []
  private var trackers: [String] = []
  var domainCount: Int { domains.count }
  init(path: String?, expectedDigest: String) {
    guard let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
    load(data: data, expectedDigest: expectedDigest)
  }
  init(data: Data, expectedDigest: String) { load(data: data, expectedDigest: expectedDigest) }
  private func load(data: Data, expectedDigest: String) {
    guard !data.isEmpty, data.count <= 16 * 1024 * 1024, String(data: data, encoding: .utf8) != nil, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedDigest,
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      json["schemaVersion"] as? Int == 1, (json["sequence"] as? Int ?? 0) >= 1,
      let categories = json["categories"] as? [String: [String]], categories.count == 6,
      let paths = json["pathRules"] as? [[String: String]], let trackerEntries = json["trackers"] as? [String] else { return }
    for category in ["sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat"] {
      guard let entries = categories[category], !entries.isEmpty, entries.count <= 500000 else { return }
      for host in entries { guard consumerBaselineDomain(host) else { return }; domains[host] = category }
    }
    for row in paths {
      guard let host = row["host"], NativeGuardPolicy.normalizeHost(host) == host,
        let path = row["pathPrefix"], path.hasPrefix("/"), !path.contains("%"), !path.contains("?"), path == path.lowercased(),
        let category = row["category"], categories[category] != nil else { return }
      pathRules.append((host, path.lowercased(), category))
    }
    guard trackerEntries.allSatisfy({ consumerBaselineDomain($0) }) else { return }
    trackers = trackerEntries
    valid = true
  }
  func check(_ input: String) -> ConsumerNativeDecision {
    guard valid else { return ConsumerNativeDecision(nil, "Mandatory protection data is unavailable. Recovery is required.") }
    guard let url = consumerCheckedURL(input) else { return ConsumerNativeDecision(nil, "This address is unsupported or contains credentials.") }
    guard let target = consumerSearchDestination(url) else { return ConsumerNativeDecision(nil, "This search shortcut or provider address cannot enforce strict search.") }
    guard let host = target.host?.lowercased() else { return ConsumerNativeDecision() }
    var candidate = host
    while true {
      if let category = domains[candidate] { return ConsumerNativeDecision(nil, "Blocked category: \(category).") }
      guard let dot = candidate.firstIndex(of: ".") else { break }; candidate = String(candidate[candidate.index(after: dot)...])
    }
    var pathSegments: [String] = []
    let decodedPath = URLComponents(url: target, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding ?? target.path
    for segment in decodedPath.lowercased().split(separator: "/") {
      if segment == ".." { if !pathSegments.isEmpty { pathSegments.removeLast() } }
      else if segment != "." { pathSegments.append(String(segment)) }
    }
    let path = "/" + pathSegments.joined(separator: "/")
    for rule in pathRules where host == rule.host || host.hasSuffix("." + rule.host) {
      if path == rule.path || path.hasPrefix(rule.path.hasSuffix("/") ? rule.path : rule.path + "/") { return ConsumerNativeDecision(nil, "Blocked category: \(rule.category).") }
      if consumerHasAmbiguousPathEncoding(target) {
        return ConsumerNativeDecision(nil, "This site's encoded address cannot be checked safely. Use its standard address.")
      }
    }
    return ConsumerNativeDecision(target)
  }
  func contentRuleGroups() -> [String] {
    var rules: [[String: Any]] = []
    for domain in domains.keys.sorted() {
      rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]"], "action": ["type": "block"]])
    }
    var groups: [String] = stride(from: 0, to: rules.count, by: 25000).compactMap { start in
      guard let data = try? JSONSerialization.data(withJSONObject: Array(rules[start..<min(start + 25000, rules.count)])) else { return nil }
      return String(data: data, encoding: .utf8)
    }
    rules.removeAll(keepingCapacity: false)
    for rule in pathRules {
      let prefix = "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: rule.host) + "(:[0-9]+)?" + consumerContentRulePath(rule.path)
      rules.append(["trigger": ["url-filter": prefix + "$"], "action": ["type": "block"]])
      rules.append(["trigger": ["url-filter": prefix + "[/?#]"], "action": ["type": "block"]])
    }
    // WKContentRuleList does not canonicalize encoded ASCII path characters
    // and cannot express alternation. Only hosts with mandatory path rules
    // reject these ambiguous spellings; queries, spaces and UTF-8 stay usable.
    for host in Set(pathRules.map { $0.host }) {
      let prefix = "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: host) + "(:[0-9]+)?/[^?#]*"
      for encoded in consumerAmbiguousPathPatterns {
        rules.append(["trigger": ["url-filter": prefix + encoded], "action": ["type": "block"]])
      }
    }
    for domain in trackers {
      rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]])
    }
    rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?duckduckgo\\.com\\.?/ac[/?#]"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?duckduckgo\\.com\\.?/ac$"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://[^/]*@"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://[^/]+\\.[/:]"], "action": ["type": "block"]])
    if let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) { groups.append(json) }
    return groups
  }
}

/// Domain rules are unchanged. Invalidate only the final path/tracker group so
/// an upgrade cannot reuse literal-path rules without recompiling all domains.
func consumerContentRuleIdentifier(digest: String, index: Int, count: Int) -> String {
  "wingman-consumer-\(index == count - 1 ? "v7" : "v5")-\(digest)-\(index)"
}

// Percent encodings of ASCII letters, digits, '-', '.', '_', '~' or '/'.
// Each expression belongs to WebKit's supported regex subset (no alternation).
private let consumerAmbiguousPathPatterns = ["%3[0-9]", "%[46][1-9a-f]", "%[57][0-9a]", "%2[d-f]", "%5f", "%7e"]
func consumerHasAmbiguousPathEncoding(_ url: URL) -> Bool {
  guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
  return consumerAmbiguousPathPatterns.contains { path.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
}

/// WebKit's content-blocker regex subset supports repetition but not `|`.
/// Repeated literal path separators must not evade the pinned path prefix.
func consumerContentRulePath(_ path: String) -> String {
  "/+" + path.split(separator: "/").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "/+")
}

func consumerCheckedURL(_ input: String) -> URL? {
  guard !input.isEmpty, input.utf8.count <= 16384, !input.contains("\\"),
    input.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
    var components = URLComponents(string: input), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
    components.user == nil, components.password == nil,
    components.port == nil || (1...65535).contains(components.port!),
    input.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*%", options: .regularExpression) == nil,
    input.range(of: "%(00|0a|0d)", options: [.regularExpression, .caseInsensitive]) == nil,
    input.range(of: "%(?![0-9a-fA-F]{2})", options: .regularExpression) == nil,
    let rawHost = components.host,
    let host = NativeGuardPolicy.normalizeHost(rawHost) else { return nil }
  components.scheme = components.scheme?.lowercased(); components.host = host
  if components.path.isEmpty { components.path = "/" }
  return components.url
}

func strictSearchURL(_ query: String) -> String? {
  guard let value = consumerSearchQuery(query) else { return nil }
  var components = URLComponents(string: "https://safe.duckduckgo.com/")!
  components.percentEncodedQuery = "q=" + consumerQueryEncode(value) + "&kp=1&kac=-1"
  return components.url?.absoluteString
}


private func consumerQueryEncode(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
}
private func consumerQueryItems(_ components: URLComponents) -> [URLQueryItem]? {
  guard let encoded = components.percentEncodedQuery, !encoded.isEmpty else { return [] }
  var result: [URLQueryItem] = []
  for part in encoded.split(separator: "&", omittingEmptySubsequences: false) {
    guard let separator = part.firstIndex(of: "=") else { return nil }
    let keyText = String(part[..<separator]).replacingOccurrences(of: "+", with: "%20")
    let valueText = String(part[part.index(after: separator)...]).replacingOccurrences(of: "+", with: "%20")
    guard let key = keyText.removingPercentEncoding, !key.isEmpty,
      key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
      let value = valueText.removingPercentEncoding else { return nil }
    result.append(URLQueryItem(name: key, value: value))
  }
  return result
}

func consumerSearchQuery(_ input: String) -> String? {
  guard input.utf16.count <= 8192 else { return nil }
  func control(_ value: UInt32) -> Bool {
    value <= 0x1f || (0x7f...0x9f).contains(value) || value == 0x061c || value == 0x200e || value == 0x200f || (0x2028...0x202e).contains(value) || (0x2066...0x2069).contains(value)
  }
  func trimSpace(_ value: UInt32) -> Bool {
    value == 0x20 || value == 0xa0 || value == 0x1680 || (0x2000...0x200a).contains(value) || value == 0x202f || value == 0x205f || value == 0x3000 || value == 0xfeff
  }
  let scalars = Array(input.unicodeScalars)
  guard !scalars.contains(where: { control($0.value) }) else { return nil }
  var start = 0
  var end = scalars.count
  while start < end && trimSpace(scalars[start].value) { start += 1 }
  while end > start && trimSpace(scalars[end - 1].value) { end -= 1 }
  guard (1...512).contains(end - start) else { return nil }
  let value = String(String.UnicodeScalarView(scalars[start..<end]))
  let bytes = Array(value.utf8)
  guard bytes.count <= 1024, let encodedRun = try? NSRegularExpression(pattern: "(?:%[0-9a-fA-F]{2})+") else { return nil }
  var probe = value
  for round in 0...8 {
    probe = String(String.UnicodeScalarView(probe.unicodeScalars.map { scalar in
      let code = scalar.value
      return UnicodeScalar((0xff01...0xff5e).contains(code) ? code - 0xfee0 : code == 0xfe57 ? 0x21 : code == 0xfe68 ? 0x5c : code)!
    }))
    guard !probe.unicodeScalars.contains(where: { control($0.value) }),
      !probe.hasPrefix("\\"), probe.range(of: "(^|[^a-zA-Z0-9_])![a-zA-Z0-9_]", options: .regularExpression) == nil else { return nil }
    let matches = encodedRun.matches(in: probe, range: NSRange(probe.startIndex..., in: probe))
    if matches.isEmpty { return value }
    guard round < 8 else { return nil }
    for match in matches.reversed() {
      guard let range = Range(match.range, in: probe) else { return nil }
      let encoded = Array(probe[range].utf8)
      var decoded = [UInt8]()
      for index in stride(from: 0, to: encoded.count, by: 3) {
        guard let byte = UInt8(String(decoding: encoded[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) else { return nil }
        decoded.append(byte)
      }
      guard let replacement = String(bytes: decoded, encoding: .utf8) else { return nil }
      probe.replaceSubrange(range, with: replacement)
    }
  }
  return nil
}


/// Only known provider navigation endpoints are rewritten. Search resources
/// keep normal cookies, CSS, scripts and pagination. No provider HTML scraping.
func consumerSearchDestination(_ url: URL) -> URL? {
  guard let host = url.host?.lowercased(), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
  let duckHosts: Set<String> = ["duckduckgo.com", "www.duckduckgo.com", "safe.duckduckgo.com", "html.duckduckgo.com", "lite.duckduckgo.com", "noai.duckduckgo.com", "start.duckduckgo.com", "duck.com", "www.duck.com", "ddg.gg"]
  let ddgRelated = host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com") || duckHosts.contains(host)
  if ddgRelated || ["google.com", "www.google.com", "bing.com", "www.bing.com", "search.brave.com", "safe.search.brave.com"].contains(host) {
    guard components.port == nil || components.port == (url.scheme == "https" ? 443 : 80),
      !components.percentEncodedPath.contains("%"), !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
    if ["/", "/html", "/html/", "/lite", "/lite/"].contains(components.path) && ddgRelated && !duckHosts.contains(host) { return nil }
  }
  let knownSearch = duckHosts.contains(host) && ["/", "/html", "/html/", "/lite", "/lite/"].contains(url.path)
  let alternative = (["google.com", "www.google.com"].contains(host) && ["/search", "/"].contains(url.path)) ||
    (["bing.com", "www.bing.com"].contains(host) && ["/search", "/", "/images/search", "/videos/search"].contains(url.path)) ||
    (["search.brave.com", "safe.search.brave.com"].contains(host) && ["/search", "/", "/images", "/videos", "/news", "/ask"].contains(url.path))
  if duckHosts.contains(host), components.path == "/l/" {
    guard let items = consumerQueryItems(components) else { return nil }
    guard url.scheme == "https", components.port == nil, components.fragment == nil,
      Set(items.map { $0.name }).count == items.count,
      items.filter({ $0.name == "uddg" }).count == 1, items.allSatisfy({ ["uddg", "rut"].contains($0.name) }),
      items.first(where: { $0.name == "rut" })?.value?.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil || !items.contains(where: { $0.name == "rut" }),
      let raw = items.first(where: { $0.name == "uddg" })?.value, raw.utf8.count <= 4096, let target = consumerCheckedURL(raw), target.scheme == "https", URLComponents(url: target, resolvingAgainstBaseURL: false)?.port == nil,
      !(duckHosts.contains(target.host ?? "") && URLComponents(url: target, resolvingAgainstBaseURL: false)?.path == "/l/") else { return nil }
    return consumerSearchDestination(target)
  }
  guard knownSearch || alternative else { return url }
  guard var items = consumerQueryItems(components) else { return nil }
  guard Set(items.map { $0.name }).count == items.count, !items.contains(where: { $0.name.lowercased() == "q" && $0.name != "q" }) else { return nil }
  let query = items.first(where: { $0.name == "q" })?.value
  if let query = query {
    guard let value = consumerSearchQuery(query), let index = items.firstIndex(where: { $0.name == "q" }) else { return nil }
    items[index] = URLQueryItem(name: "q", value: value)
  }
  if alternative {
    if query == nil { return URL(string: "https://safe.duckduckgo.com/?kp=1&kac=-1") }
    guard let raw = strictSearchURL(query!) else { return nil }; return URL(string: raw)
  }
  components.scheme = "https"; components.host = "safe.duckduckgo.com"; components.port = nil; components.fragment = nil
  // HTML/lite pagination can use provider POST; retaining the endpoint keeps
  // ordinary refinement and subsequent results, with strict host enforcement.
  components.percentEncodedQuery = (items.filter { !["kp", "kac"].contains($0.name.lowercased()) } + [URLQueryItem(name: "kp", value: "1"), URLQueryItem(name: "kac", value: "-1")]).map { consumerQueryEncode($0.name) + "=" + consumerQueryEncode($0.value ?? "") }.joined(separator: "&")
  if query == nil && items.isEmpty { components.percentEncodedQuery = "kp=1&kac=-1" }
  return components.url
}

// Legacy restricted-reader rule helpers. These are never used by consumer views.
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

private let strictSearchCSS = "https://safe.duckduckgo.com/dist/lr.48ddfe4eadf6a534e93f.css"

/// No page/query-derived rules are written to WebKit's persistent rule store.
func strictSearchContentRuleJSON(documentOrigin: String = "https://safe.duckduckgo.com", styleURL: String = "https://safe.duckduckgo.com/dist/lr.48ddfe4eadf6a534e93f.css") -> String? {
  let rules: [[String: Any]] = [
    ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
    ["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: documentOrigin) + "/lite/\\?q=[A-Za-z0-9._~%\\-]+&kp=1$", "url-filter-is-case-sensitive": true, "resource-type": ["document"]], "action": ["type": "ignore-previous-rules"]],
    ["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: styleURL) + "$", "url-filter-is-case-sensitive": true, "resource-type": ["style-sheet"]], "action": ["type": "ignore-previous-rules"]],
    ["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]],
    ["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "input,textarea,select,[contenteditable]"]],
  ]
  guard let bytes = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
  return String(data: bytes, encoding: .utf8)
}

/// Shared with the owned WebKit fixture. Resource rules alone do not grant
/// navigation: only the explicitly opened, current top-level GET may proceed.
func protectedAllowsInitialNavigation(isMainFrame: Bool, method: String?, requestedURL: String, currentURL: String, initial: Bool, scopePermitted: Bool) -> Bool {
  isMainFrame && method == "GET" && initial && scopePermitted && requestedURL == currentURL
}
