import Flutter
import UIKit
import WebKit
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static var browserBridge: BrowserNativeBridge?
  static var pendingURL: String?

  static func receive(_ url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, url.user == nil, url.absoluteString.count < 16384 else { return }
    if browserBridge?.discardingHandoffLinks == true { return }
    if let bridge = browserBridge, bridge.initialized {
      bridge.channel.invokeMethod("incomingUri", arguments: url.absoluteString)
    } else { pendingURL = url.absoluteString }
  }

  override func application(_ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    AppDelegate.receive(url)
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WingmanBrowser") else { return }
    AppDelegate.browserBridge = BrowserNativeBridge(registrar: registrar)
  }
}

/// Legacy native services contain no content loader or script evaluator.
/// Consumer WebKit rendering uses the protected factory with a pinned baseline.
final class BrowserNativeBridge {
  let channel: FlutterMethodChannel
  var initialized = false
  var discardingHandoffLinks = false
  let protectedBrowser: ProtectedWebBridge
  private var clearing = false
  private var quarantineCompletedInProcess = false
  private var quarantinePurgeCount = 0
  private static let consumerMigrationVersion = 2
  private static let migrationKey = "wingman.consumer.webkit.migration"
  static var hasDefaultBrowserEntitlement: Bool {
    // This checkout has no Apple-approved managed browser entitlement. Only
    // enable this build flag together with Apple's granted signing entitlement.
    #if WINGMAN_DEFAULT_BROWSER_ENTITLEMENT
    return true
    #else
    return false
    #endif
  }

  init(registrar: FlutterPluginRegistrar) {
    // Incomplete downloads never become a restored private-session artifact.
    let temporary = FileManager.default.temporaryDirectory
    for url in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("WingmanDownload-") {
      try? FileManager.default.removeItem(at: url)
    }
    protectedBrowser = ProtectedWebBridge(registrar: registrar)
    channel = FlutterMethodChannel(name: "wingman/browser", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func contentViewCount(_ view: UIView) -> Int {
    (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + contentViewCount($1) }
  }

  private func activeTextInputCount(_ view: UIView) -> Int {
    ((view is UITextInput && view.isFirstResponder) ? 1 : 0)
      + view.subviews.reduce(0) { $0 + activeTextInputCount($1) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "discardHandoffIncoming":
      // Deny-only; no guest link can be replayed into the restored owner shell.
      protectedBrowser.hideAll()
      AppDelegate.pendingURL = nil
      initialized = false
      discardingHandoffLinks = true
      result(nil)
    case "initialize":
      if discardingHandoffLinks { AppDelegate.pendingURL = nil }
      discardingHandoffLinks = false
      protectedBrowser.restoreOwner()
      initialized = true
      result(AppDelegate.pendingURL)
      AppDelegate.pendingURL = nil
    case "privateAvailable": result(true)
    case "defaultBrowser":
      guard Self.hasDefaultBrowserEntitlement,
        let settings = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
      UIApplication.shared.open(settings, options: [:]) { result($0) }
    case "setSensitiveContent": result(nil) // Every inactive scene is covered natively.
    case "handoffCapabilities":
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let authentication = LAContext()
      // Read prerequisites only. Never prompt, enroll or change device settings.
      let available = authentication.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
      authentication.invalidate()
      result(["staticOnly": true, "liveBrowsing": false,
        "contentViews": scenes.flatMap { $0.windows }.reduce(0) { $0 + contentViewCount($1) },
        "deviceAuthenticationAvailable": available])
    case "capabilityState":
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      result(["capability": "consumerWeb", "liveBrowsing": true,
        "contentViews": scenes.flatMap { $0.windows }.reduce(0) { $0 + contentViewCount($1) },
        "quarantineCompletedInProcess": quarantineCompletedInProcess,
        "quarantinePurgeCount": quarantinePurgeCount,
        "handoffIncomingDiscarded": discardingHandoffLinks, "incomingReady": initialized,
        "activeTextInputs": scenes.flatMap { $0.windows }.reduce(0) { $0 + activeTextInputCount($1) },
        "shieldVisible": scenes.contains { ($0.delegate as? SceneDelegate)?.privacyShieldVisible == true }])
    case "normalizeHost": result(NativeGuardPolicy.normalizeHost(args["host"] as? String ?? ""))
    case "localDataDirectory":
      do {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("Wingman", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        result(directory.path)
      } catch {
        result(FlutterError(code: "local_storage_unavailable", message: "Local storage could not be opened.", details: nil))
      }
    case "quarantineLegacyContent":
      // Versioned upgrade cleanup. Never delete newly valid normal cookies or
      // storage at each launch, Flutter-root rebuild or app resume.
      if UserDefaults.standard.integer(forKey: Self.migrationKey) >= Self.consumerMigrationVersion {
        quarantineCompletedInProcess = true
        protectedBrowser.quarantineCompleted { result(nil) }; return
      }
      clearData(types: WKWebsiteDataStore.allWebsiteDataTypes(), quarantine: true, result: result)
    case "clearData":
      protectedBrowser.closeAll()
      var types = Set<String>()
      if args["cookies"] as? Bool == true { types.insert(WKWebsiteDataTypeCookies) }
      if args["cache"] as? Bool == true {
        types.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache])
      }
      if args["storage"] as? Bool == true {
        types.formUnion([WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage,
          WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases,
          WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFetchCache])
      }
      clearData(types: types, result: result)
    case "stop", "pause", "hideForGuard", "close": result(nil) // No retained views.
    case "closedViewReleased": result(true)
    default:
      // Applies equally to normal/student/private, simulator/device and all
      // build modes. There is no mutable policy or debug activation channel.
      result(FlutterError(code: "bundled_content_only",
        message: "This capability is unavailable in the bundled library.", details: nil))
    }
  }

  private func clearData(types: Set<String>, quarantine: Bool = false, result: @escaping FlutterResult) {
    guard !clearing else {
      result(FlutterError(code: "cleanup_pending", message: "Legacy site-data cleanup is still pending.", details: nil)); return
    }
    guard !types.isEmpty else { result(nil); return }
    clearing = true
    protectedBrowser.cleanupStarted()
    if quarantine { quarantinePurgeCount += 1 }
    // The current visual views are already released and use nonpersistent stores.
    // Remove only the prior persistent default store; this constructs no view.
    WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
      // Only WebKit's completion acknowledges the purge. Pending, rejected or
      // timed-out Dart waits cannot set this flag; explicit clearData requests
      // always perform their requested deletion and never consult this receipt.
      func finish() {
        self.clearing = false
        self.protectedBrowser.cleanupFinished()
        result(nil)
      }
      if quarantine {
        self.quarantineCompletedInProcess = true
        UserDefaults.standard.set(Self.consumerMigrationVersion, forKey: Self.migrationKey)
        self.protectedBrowser.quarantineCompleted(completion: finish)
      } else { finish() }
    }
  }
}
