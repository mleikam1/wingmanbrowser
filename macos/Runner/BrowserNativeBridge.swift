import Cocoa
import FlutterMacOS
import WebKit

/// Application services contain no page script evaluator or protection override.
final class BrowserNativeBridge {
  let channel: FlutterMethodChannel
  let protectedBrowser: ProtectedWebBridge
  private(set) var initialized = false
  private(set) var discardingHandoffLinks = false
  private var pendingURL: String?
  private var clearing = false
  private var prepared = false
  static let hasDefaultBrowserEntitlement = false

  init(registrar: FlutterPluginRegistrar) {
    // Only abandoned staging files inside this new app's sandbox are removed.
    let temporary = FileManager.default.temporaryDirectory
    for url in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] where url.lastPathComponent.hasPrefix("WingmanDownload-") {
      try? FileManager.default.removeItem(at: url)
    }
    protectedBrowser = ProtectedWebBridge(registrar: registrar)
    channel = FlutterMethodChannel(name: "wingman/browser", binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
  }

  func receive(_ url: URL) {
    guard !discardingHandoffLinks, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, url.user == nil, url.password == nil, url.absoluteString.count <= 16384 else { return }
    if initialized { channel.invokeMethod("incomingUri", arguments: url.absoluteString) }
    else { pendingURL = url.absoluteString }
  }

  private func contentViewCount(_ view: NSView) -> Int {
    (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + contentViewCount($1) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      discardingHandoffLinks = false; protectedBrowser.restoreOwner(); initialized = true
      result(pendingURL); pendingURL = nil
    case "discardHandoffIncoming":
      protectedBrowser.hideAll(); pendingURL = nil; initialized = false; discardingHandoffLinks = true; result(nil)
    case "quarantineLegacyContent":
      // This newly introduced desktop ID has no retired iOS/Android installation
      // to migrate. Startup prepares mandatory rules and never purges cookies.
      protectedBrowser.quarantineCompleted { self.prepared = true; result(nil) }
    case "privateAvailable": result(true)
    case "requestDefaultBrowser", "defaultBrowser": result(false)
    case "setSensitiveContent":
      (NSApp.delegate as? AppDelegate)?.setSensitive(args["sensitive"] as? Bool == true); result(nil)
    case "handoffCapabilities":
      result(["staticOnly": false, "liveBrowsing": false, "contentViews": NSApp.windows.compactMap { $0.contentView }.reduce(0) { $0 + contentViewCount($1) }, "deviceAuthenticationAvailable": false])
    case "capabilityState":
      result(["capability": "consumerWeb", "liveBrowsing": prepared,
        "contentViews": NSApp.windows.compactMap { $0.contentView }.reduce(0) { $0 + contentViewCount($1) },
        "quarantineCompletedInProcess": prepared, "quarantinePurgeCount": 0,
        "handoffIncomingDiscarded": discardingHandoffLinks, "incomingReady": initialized,
        "shieldVisible": (NSApp.delegate as? AppDelegate)?.privacyShieldVisible ?? false])
    case "normalizeHost": result(NativeGuardPolicy.normalizeHost(args["host"] as? String ?? ""))
    case "localDataDirectory":
      do {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wingman", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        result(directory.path)
      } catch { result(FlutterError(code: "local_storage_unavailable", message: "Local storage could not be opened.", details: nil)) }
    case "clearData":
      guard !clearing else { result(FlutterError(code: "cleanup_pending", message: "Site-data cleanup is still pending.", details: nil)); return }
      var types = Set<String>()
      if args["cookies"] as? Bool == true { types.insert(WKWebsiteDataTypeCookies) }
      if args["cache"] as? Bool == true { types.formUnion([WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeOfflineWebApplicationCache]) }
      if args["storage"] as? Bool == true { types.formUnion([WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases, WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFetchCache]) }
      guard !types.isEmpty else { result(nil); return }
      clearing = true; protectedBrowser.cleanupStarted()
      WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
        self.clearing = false; self.protectedBrowser.cleanupFinished(); result(nil)
      }
    case "hideForGuard": protectedBrowser.hideAll(); result(nil)
    case "pause": protectedBrowser.pauseAll(); result(nil)
    case "close": protectedBrowser.closeAll(); result(nil)
    case "stop": result(nil)
    case "closedViewReleased": result(true)
    default: result(FlutterError(code: "native_method_unavailable", message: "This operation is unavailable on macOS.", details: nil))
    }
  }
}
