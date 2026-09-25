import FlutterMacOS
import Cocoa
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
  private var views: [Int64: ProtectedWebView] = [:]
  private var retainedViews: [ProtectedWebView] { Array(views.values) }
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
    channel = FlutterMethodChannel(name: "wingman/protected-browser", binaryMessenger: registrar.messenger)
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
  func testDocumentIdentity(_ viewId: Int64) -> (url: String, generation: Int)? {
    guard let view = views[viewId] else { return nil }
    return (view.currentURL, view.documentGeneration)
  }
  #endif
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let frame = NSRect.zero
    let values = args as? [String: Any] ?? [:]
    if let token = values["windowToken"] as? String, let pending = pendingWindows.removeValue(forKey: token) {
      let view = pending.view
      if mayOpen, foreground, pending.isCurrent,
        (values["edition"] as? String) == "consumer", view.privateMode == (values["private"] as? Bool == true),
        let tabId = values["tabId"] as? String, !tabId.isEmpty, tabId.count <= 100, view.matchesRestrictions(values) {
        view.adoptIdentity(viewId: viewId, tabId: tabId, frame: frame)
        views[viewId] = view
        return view.view()
      }
      view.release()
    }
    let view = ProtectedWebView(frame: frame, id: viewId, tabId: values["tabId"] as? String ?? "", privateMode: values["private"] as? Bool == true,
      consumer: (values["edition"] as? String ?? "unknown") == "consumer", restrictions: values, bridge: self)
    views[viewId] = view
    return view.view()
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
        "resourceCountersObservable": false, "resourceCounterScope": "unobservable",
        "findInPage": true, "media": true, "originPermissions": true, "policyUpdatesAvailable": !updateKeys.isEmpty, "defaultBrowserAvailable": BrowserNativeBridge.hasDefaultBrowserEntitlement,
        "reason": mayOpen ? NSNull() as Any : "Mandatory protection data is unavailable. Recovery is required." as Any]); return
    }
    if call.method == "state", args["viewId"] == nil {
      result(["views": retainedViews.filter { $0.hasRenderer }.count, "ready": ready, "foreground": foreground,
        "handoffBlocked": handoffBlocked, "cleanupPending": cleanupPending, "baselineValid": baseline.valid,
        "preparedRuleSets": compiled.count, "ruleCompilationCount": compilationCount, "domainCount": baseline.domainCount, "policyRecoveryRequired": updateRecoveryRequired, "policySHA256": activeDigest]); return
    }
    guard let id = (args["viewId"] as? NSNumber)?.int64Value, let view = views[id] else { error(result); return }
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

/// Native sheets can return an older export while a new upload is pending.
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
  weak var window: NSWindow?
  let cancel: () -> Void
  init(_ window: NSWindow, cancel: @escaping () -> Void) { self.window = window; self.cancel = cancel }
}

private final class ProtectedWebView: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
  private(set) var id: Int64
  private(set) var tabId: String
  let privateMode: Bool
  let consumer: Bool
  weak var bridge: ProtectedWebBridge?
  private let container: NSView
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
  private var downloadTickets: [ObjectIdentifier: (generation: Int, origin: String?)] = [:]
  private var downloadGestureUntil = Date.distantPast
  private var blockedDomains = Set<String>()
  private var blockedSearch = false
  private var blockedURLs = Set<String>()
  private(set) var documentGeneration = 0
  private var lifecycleRevision = 0
  private var uploadGeneration = -1
  private weak var uploadRenderer: WKWebView?
  private var uploadOrigin: String?
  private var lastNewWindow: (String, Date)?
  private var additionalRules: WKContentRuleList?
  private var restrictionVersion = 0
  private var restrictionsReady = true
  private var restrictionFailure = false
  private var exportedTemporary: [ObjectIdentifier: URL] = [:]
  private var sharingPicker: NSSharingServicePicker?
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
     "resourceCountersObservable": false, "resourceCounterScope": "unobservable",
     "hasRenderer": hasRenderer, "private": privateMode, "javascript": true, "resourceRulesInstalled": hasRenderer,
     "strictSearch": URL(string: currentURL)?.host == "safe.duckduckgo.com"]
  }
  init(frame: CGRect, id: Int64, tabId: String, privateMode: Bool, consumer: Bool, restrictions: [String: Any], bridge: ProtectedWebBridge, inheriting opener: ProtectedWebView? = nil) {
    self.id = id; self.tabId = tabId; self.privateMode = privateMode; self.consumer = consumer; self.bridge = bridge
    foreground = bridge.isForeground
    container = NSView(frame: frame); container.wantsLayer = true; container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    super.init()
    if let opener = opener {
      blockedDomains = opener.blockedDomains; blockedURLs = opener.blockedURLs; blockedSearch = opener.blockedSearch
      additionalRules = opener.additionalRules; restrictionsReady = opener.restrictionsReady; restrictionFailure = opener.restrictionFailure
      active = false; awaitingWindowAdoption = true; scriptWindow = true
    } else { updateRestrictions(restrictions) {} }
  }
  func view() -> NSView { container }
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
      return ConsumerNativeDecision(nil, "This destination is blocked by an additional restriction.", reasonCode: .blockAdditionalRestriction)
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
    let restoreRequest = requestId
    // Adding a restriction closes the old renderer before new resource rules
    // compile. A live script cannot race the newly tightened policy.
    release()
    let restoreRevision = lifecycleRevision
    var hosts = Array(next)
    if search { hosts += ["safe.duckduckgo.com", "duckduckgo.com"] }
    if hosts.isEmpty && urls.isEmpty {
      if let list = additionalRules { web?.configuration.userContentController.remove(list) }
      additionalRules = nil; restrictionsReady = true; if let restoreURL = restoreURL, requestId == restoreRequest, lifecycleRevision == restoreRevision { open(restoreURL, request: restoreRequest) }; completion(); return
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
      self.additionalRules = list; self.web?.configuration.userContentController.add(list); self.restrictionsReady = true; if let restoreURL = restoreURL, self.requestId == restoreRequest, self.lifecycleRevision == restoreRevision { self.open(restoreURL, request: restoreRequest) }; completion()
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
    renderer.autoresizingMask = [.width, .height]
    renderer.navigationDelegate = self; renderer.uiDelegate = self
    renderer.allowsLinkPreview = false // Preview can navigate outside our tab delegate.
    renderer.allowsBackForwardNavigationGestures = true
    if #available(macOS 13.3, *) { renderer.isInspectable = false }
    web = renderer
    consumerSetWebActivity(renderer, allowed: active && foreground)
    observations = [
      renderer.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.title, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.url, options: [.new]) { [weak self] renderer, _ in self?.observedURL(renderer) },
      renderer.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.emit() },
      renderer.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.emit() },
    ]
    container.addSubview(renderer)
    return renderer
  }
  private func observedURL(_ renderer: WKWebView, committed: Bool = false) {
    guard renderer === web, !awaitingWindowAdoption, let raw = renderer.url?.absoluteString,
      raw != "about:blank" else { return }
    // KVO can also expose a provisional redirect. Only the committed history
    // item describes the interactive document; navigation delegates own pending
    // network loads and preserve that document when a redirect is cancelled.
    guard committed || renderer.backForwardList.currentItem?.url.absoluteString == raw else { return }
    let decision = checked(raw)
    guard bridge?.mayOpen == true, decision.url != nil else {
      // History APIs can expose a newly denied path without a network navigation
      // delegate callback. Retire that document instead of leaving it interactive.
      renderer.stopLoading(); blocked(raw, decision); release(); emit(); return
    }
    currentURL = raw
    committedURL = raw
    // URL observation includes pushState/replaceState and fragment/history moves.
    // It must not load again or invalidate a still-owned document's callbacks.
    emit()
  }
  func open(_ url: URL, request: Int64) {
    requestId = request; errorText = nil
    if !restrictionsReady {
      let revision = lifecycleRevision
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self = self, self.requestId == request, self.lifecycleRevision == revision else { return }; self.open(url, request: request)
      }
      return
    }
    guard !restrictionFailure else {
      blocked(url.absoluteString, "Protection rules are unavailable.", reasonCode: .blockPolicyUnavailable); return
    }
    let decision = checked(url.absoluteString)
    guard decision.url != nil else { blocked(url.absoluteString, decision); return }
    guard let renderer = ensureRenderer() else { errorText = "Consumer browsing is unavailable in this edition."; emit(); return }
    currentURL = url.absoluteString
    var request = URLRequest(url: url)
    request.setValue("1", forHTTPHeaderField: "DNT"); request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    renderer.load(request); emit()
  }
  func setActive(_ value: Bool) { active = value; if !value { cancelOwnedPresentations() }; if let web = web { consumerSetWebActivity(web, allowed: active && foreground) }; emit() }
  func setForeground(_ value: Bool) { foreground = value; if !value { cancelOwnedPresentations() }; if let web = web { consumerSetWebActivity(web, allowed: active && foreground) } }
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
  private func cancelOwnedPresentations() {
    uploadReply?.cancel(nil); uploadReply = nil; uploadRenderer = nil; uploadOrigin = nil
    let owned = presentations; presentations.removeAll()
    for presentation in owned {
      presentation.cancel()
      if let window = presentation.window { window.sheetParent?.endSheet(window, returnCode: .cancel); window.orderOut(nil) }
    }
    sharingPicker?.close(); sharingPicker = nil
  }
  func release() {
    lifecycleRevision += 1
    bridge?.cancelWindows(openedBy: self)
    windowToken = nil; awaitingWindowAdoption = false
    let deferred = deferredWindowNavigations; deferredWindowNavigations.removeAll(); deferred.forEach { $0.cancel() }
    committedURL = ""; policyCancellationUntil = .distantPast
    cancelOwnedPresentations()
    for url in exportedTemporary.values { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    exportedTemporary.removeAll()
    for (_, entry) in downloads { entry.0.delegate = nil; entry.0.cancel { _ in }; if let url = entry.1 { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
    downloads.removeAll(); downloadTickets.removeAll(); observations.forEach { $0.invalidate() }; observations.removeAll()
    if let web = web { consumerSetWebActivity(web, allowed: false) }
    web?.stopLoading(); web?.navigationDelegate = nil; web?.uiDelegate = nil; web?.removeFromSuperview(); web = nil
  }
  private func blocked(_ raw: String, _ decision: ConsumerNativeDecision) {
    blocked(raw, decision.reason, reasonCode: decision.reasonCode, category: decision.category)
  }
  private func blocked(_ raw: String, _ reason: String, reasonCode: ConsumerNativeReasonCode = .blockUnsupportedCapability, category: String? = nil) {
    policyCancellationUntil = Date().addingTimeInterval(15)
    errorText = nil
    if !committedURL.isEmpty { currentURL = committedURL }
    emit()
    // Native policy sends only a typed explanation, never denied page metadata.
    bridge?.emit("navigationBlocked", ["viewId": id, "requestId": requestId, "reason": reason,
      "reasonCode": reasonCode.rawValue, "category": category ?? NSNull() as Any])
  }
  func find(_ query: String?, forward: Bool, result: @escaping FlutterResult) {
    if let query = query { findQuery = String(query.prefix(512)) }
    guard let web = web else { result(false); return }
    let configuration = WKFindConfiguration(); configuration.backwards = !forward; configuration.wraps = true
    web.find(findQuery, configuration: configuration) { result($0.matchFound) }
  }
  private var presenter: NSWindow? { container.window }
  private func presentOwned(_ alert: NSAlert, from presenter: NSWindow, cancel: @escaping () -> Void = {}, completed: @escaping (NSApplication.ModalResponse) -> Void) {
    presentations = presentations.filter { $0.window != nil }
    presentations.append(ConsumerPresentation(alert.window, cancel: cancel))
    alert.beginSheetModal(for: presenter, completionHandler: completed)
  }
  private func trackPanel(_ panel: NSSavePanel, cancel: @escaping () -> Void) {
    presentations = presentations.filter { $0.window != nil }
    presentations.append(ConsumerPresentation(panel, cancel: cancel))
  }
  func share() {
    guard active, foreground, let url = checked(currentURL).url, presenter != nil else { return }
    sharingPicker?.close()
    let picker = NSSharingServicePicker(items: [url]); sharingPicker = picker
    picker.show(relativeTo: NSRect(x: 12, y: container.bounds.height - 12, width: 1, height: 1), of: container, preferredEdge: .minY)
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
    guard let target = decision.url else { decisionHandler(.cancel); if action.targetFrame?.isMainFrame != false { blocked(raw, decision) }; return }
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
    guard webView === web, bridge?.mayOpen == true, let raw = webView.url?.absoluteString else { return }
    let decision = checked(raw)
    if decision.url == nil { webView.stopLoading(); blocked(raw, decision) }
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
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { observedURL(webView, committed: true) }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if webView === web { errorText = nil; observedURL(webView, committed: true) } }
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
    guard let target = decision.url else { blocked(raw, decision); return nil }
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
    let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(message.prefix(2000)); alert.addButton(withTitle: "OK")
    presentOwned(alert, from: presenter, cancel: { reply.resolve(()) }) { _ in reply.resolve(()) }
  }
  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    guard webView === web, active, foreground, let presenter = presenter else { completionHandler(false); return }
    let reply = ConsumerReply(completionHandler)
    let generation = documentGeneration, origin = consumerOrigin(currentURL)
    let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(message.prefix(2000))
    alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "OK")
    presentOwned(alert, from: presenter, cancel: { reply.resolve(false) }) { [weak self, weak webView] response in
      reply.resolve(response == .alertSecondButtonReturn && self?.web === webView && self?.active == true && self?.foreground == true && self?.documentGeneration == generation && consumerOrigin(self?.currentURL ?? "") == origin)
    }
  }
  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    guard webView === web, active, foreground, let presenter = presenter else { completionHandler(nil); return }
    let reply = ConsumerReply(completionHandler)
    let generation = documentGeneration, origin = consumerOrigin(currentURL)
    let alert = NSAlert(); alert.messageText = frame.securityOrigin.host; alert.informativeText = String(prompt.prefix(2000))
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 28)); field.stringValue = String((defaultText ?? "").prefix(2000)); alert.accessoryView = field
    alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "OK")
    presentOwned(alert, from: presenter, cancel: { reply.resolve(nil) }) { [weak self, weak webView] response in
      reply.resolve(response == .alertSecondButtonReturn && self?.web === webView && self?.active == true && self?.foreground == true && self?.documentGeneration == generation && consumerOrigin(self?.currentURL ?? "") == origin ? String(field.stringValue.prefix(2000)) : nil)
    }
  }
  func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
    guard webView === web, bridge?.mayOpen == true, active, foreground, uploadReply == nil, let raw = frame.request.url?.absoluteString, checked(raw).url != nil, let presenter = presenter else { completionHandler(nil); return }
    guard frame.isMainFrame, let origin = consumerOrigin(raw), origin == consumerOrigin(currentURL) else { completionHandler(nil); return }
    uploadGeneration = documentGeneration; uploadRenderer = web; uploadOrigin = origin
    let picker = NSOpenPanel(); picker.canChooseFiles = true; picker.canChooseDirectories = parameters.allowsDirectories
    picker.allowsMultipleSelection = parameters.allowsMultipleSelection
    let reply = ConsumerOwnedReply(owner: picker, callback: completionHandler); uploadReply = reply
    trackPanel(picker, cancel: { reply.cancel(nil) })
    picker.beginSheetModal(for: presenter) { [weak self, weak picker] response in
      guard let self = self, let picker = picker else { reply.cancel(nil); return }
      guard self.uploadReply === reply else { reply.cancel(nil); return }
      let valid = response == .OK && self.active && self.foreground && self.bridge?.mayOpen == true && self.uploadRenderer === self.web && self.uploadGeneration == self.documentGeneration && self.uploadOrigin == consumerOrigin(self.currentURL) && self.checked(self.currentURL).url != nil
      self.uploadReply = nil; self.uploadRenderer = nil; self.uploadOrigin = nil
      reply.resolve(from: picker, value: valid ? picker.urls : nil)
    }
  }
  func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
    guard webView === web, bridge?.mayOpen == true, active, foreground, origin.protocol == "https", let frameURL = frame.request.url, frameURL.host == origin.host,
      checked(frameURL.absoluteString).url != nil else { decisionHandler(.deny); return }
    decisionHandler(.prompt) // WebKit's origin-scoped prompt plus OS permission.
  }
  private func ownsDownload(_ download: WKDownload) -> Bool {
    guard web != nil, bridge?.mayOpen == true, !awaitingWindowAdoption, downloads[ObjectIdentifier(download)]?.0 === download,
      let ticket = downloadTickets[ObjectIdentifier(download)] else { return false }
    return ticket.generation == documentGeneration && ticket.origin == consumerOrigin(currentURL)
  }
  private func acceptDownload(_ download: WKDownload, from source: WKWebView) {
    guard source === web, bridge?.mayOpen == true, active, foreground, !awaitingWindowAdoption else {
      download.delegate = nil; download.cancel { _ in }; return
    }
    downloads[ObjectIdentifier(download)] = (download, nil)
    downloadTickets[ObjectIdentifier(download)] = (documentGeneration, consumerOrigin(currentURL)); download.delegate = self
  }
  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { acceptDownload(download, from: webView) }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { acceptDownload(download, from: webView) }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    guard ownsDownload(download), active, foreground, let url = response.url, checked(url.absoluteString).url != nil, let presenter = presenter else { completionHandler(nil); return }
    let reply = ConsumerReply(completionHandler)
    let filename = String(URL(fileURLWithPath: suggestedFilename).lastPathComponent.prefix(180))
    let safeName = filename.isEmpty || filename == "." || filename == ".." ? "download" : filename
    let alert = NSAlert(); alert.messageText = "Download file?"; alert.informativeText = "\(safeName)\nFrom \(url.host ?? "this website")"
    alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Download")
    presentOwned(alert, from: presenter, cancel: { reply.resolve(nil) }) { [weak self] response in
      guard let self = self, response == .alertSecondButtonReturn, self.ownsDownload(download), self.active, self.foreground, self.checked(url.absoluteString).url != nil else { reply.resolve(nil); return }
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WingmanDownload-" + UUID().uuidString, isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(safeName)
        self.downloads[ObjectIdentifier(download)] = (download, destination); reply.resolve(destination)
      } catch { reply.resolve(nil) }
    }
  }
  func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
    guard ownsDownload(download), let raw = request.url?.absoluteString, let target = checked(raw).url, target.absoluteString == raw else { decisionHandler(.cancel); return }
    decisionHandler(.allow)
  }
  func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) { completionHandler(ownsDownload(download) ? .performDefaultHandling : .cancelAuthenticationChallenge, nil) }
  func downloadDidFinish(_ download: WKDownload) {
    let current = ownsDownload(download)
    downloadTickets.removeValue(forKey: ObjectIdentifier(download))
    guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)), let url = entry.1 else { return }
    download.delegate = nil
    guard current, let presenter = presenter, active, foreground else { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
    let renderer = web, generation = documentGeneration
    let picker = NSSavePanel(); picker.nameFieldStringValue = url.lastPathComponent
    exportedTemporary[ObjectIdentifier(picker)] = url
    trackPanel(picker, cancel: { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) })
    picker.beginSheetModal(for: presenter) { [weak self, weak picker] response in
      defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
      guard let self = self, let picker = picker else { return }
      self.exportedTemporary.removeValue(forKey: ObjectIdentifier(picker))
      guard response == .OK, let destination = picker.url, self.web === renderer, self.documentGeneration == generation, self.active, self.foreground, self.bridge?.mayOpen == true else { return }
      let access = destination.startAccessingSecurityScopedResource(); defer { if access { destination.stopAccessingSecurityScopedResource() } }
      do {
        // NSSavePanel owns overwrite confirmation. Copy/move files without
        // reading an arbitrarily large download into application memory.
        if FileManager.default.fileExists(atPath: destination.path) {
          _ = try FileManager.default.replaceItemAt(destination, withItemAt: url)
        } else { try FileManager.default.copyItem(at: url, to: destination) }
      }
      catch { self.bridge?.emit("downloadFailed", ["viewId": self.id, "requestId": self.requestId, "reason": "The file could not be saved."]) }
    }
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    let current = ownsDownload(download)
    downloadTickets.removeValue(forKey: ObjectIdentifier(download))
    guard let entry = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    download.delegate = nil
    if let url = entry.1 { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    guard current else { return }
    bridge?.emit("downloadFailed", ["viewId": id, "requestId": requestId, "reason": "The download could not finish."])
  }
}
