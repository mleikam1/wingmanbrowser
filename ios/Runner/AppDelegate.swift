import Flutter
import UIKit
import WebKit
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static var browserBridge: BrowserNativeBridge?
  static var pendingURL: String?

  static func receive(_ url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
      url.host != nil, url.user == nil, url.absoluteString.count < 16384 else { return }
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

/// The only app/native bridge is Flutter's channel. Websites receive no JS bridge.
final class BrowserNativeBridge {
  let channel: FlutterMethodChannel
  let registrar: FlutterPluginRegistrar
  var initialized = false
  private var delegates: [Int64: BrowserNavigationProxy] = [:]
  private var findQueries: [Int64: String] = [:]

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "wingman/browser", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value ?? -1
    let view = FWFWebViewFlutterWKWebViewExternalAPI.webView(forIdentifier: id, withPluginRegistrar: registrar)
    switch call.method {
    case "initialize":
      initialized = true; result(AppDelegate.pendingURL); AppDelegate.pendingURL = nil
    case "privateAvailable": result(true)
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
    case "privateConfiguration":
      guard let configuration = FWFWebViewFlutterWKWebViewExternalAPI.wingmanConfiguration(
        forIdentifier: id, registrar: registrar) else {
        result(FlutterError(code: "private_unavailable", message: "Private storage could not be configured.", details: nil)); return
      }
      configuration.websiteDataStore = .nonPersistent()
      result(!configuration.websiteDataStore.isPersistent)
    case "configure":
      guard let view = view else { result(false); return }
      let privateMode = args["private"] as? Bool == true
      guard !privateMode || !view.configuration.websiteDataStore.isPersistent else {
        result(FlutterError(code: "private_unavailable", message: "Private storage unavailable.", details: nil)); return
      }
      view.configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
      view.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
      if #available(iOS 16.4, *) {
        #if DEBUG
        view.isInspectable = true
        #else
        view.isInspectable = false
        #endif
      }
      let proxy = BrowserNavigationProxy(original: view.navigationDelegate, privateMode: privateMode,
        message: { [weak self] text in self?.channel.invokeMethod("message", arguments: text) },
        navigationSettled: { [weak self] url in
          self?.channel.invokeMethod("navigationSettled", arguments: ["id": id, "attemptedUrl": url])
        })
      delegates[id] = proxy
      view.navigationDelegate = proxy
      result(true)
    case "stop": view?.stopLoading(); result(nil)
    case "pause":
      view?.setAllMediaPlaybackSuspended(true) { result(nil) }
      if view == nil { result(nil) }
    case "resume":
      view?.setAllMediaPlaybackSuspended(false) { result(nil) }
      if view == nil { result(nil) }
    case "desktop":
      view?.configuration.defaultWebpagePreferences.preferredContentMode = args["enabled"] as? Bool == true ? .desktop : .mobile
      view?.customUserAgent = nil
      result(nil)
    case "find", "findNext":
      guard let view = view else { result(false); return }
      if #available(iOS 14.0, *) {
        let configuration = WKFindConfiguration()
        configuration.wraps = true
        configuration.backwards = args["forward"] as? Bool == false
        if let query = args["query"] as? String { findQueries[id] = query }
        view.find(findQueries[id] ?? "", configuration: configuration) { found in result(found.matchFound) }
      } else { result(false) }
    case "close":
      guard let view = view else { result(nil); return }
      view.stopLoading()
      view.navigationDelegate = nil
      view.uiDelegate = nil
      view.removeFromSuperview()
      delegates.removeValue(forKey: id)
      findQueries.removeValue(forKey: id)
      if !view.configuration.websiteDataStore.isPersistent {
        view.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
          modifiedSince: .distantPast) { result(nil) }
      } else { result(nil) }
    case "clearData":
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
      WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { result(nil) }
    case "requestPermissions": result(true) // WebKit presents OS permission prompts after explicit app approval.
    case "defaultBrowser":
      guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
      UIApplication.shared.open(url) { result($0) }
    default: result(FlutterMethodNotImplemented)
    }
  }
}

/// Adds native WKDownload support while forwarding the official plugin's navigation callbacks.
final class BrowserNavigationProxy: NSObject, WKNavigationDelegate, WKDownloadDelegate {
  private let original: WKNavigationDelegate?
  private let privateMode: Bool
  private let message: (String) -> Void
  private let navigationSettled: (String) -> Void
  private var currentNavigation: WKNavigation?
  private var downloadNavigation: WKNavigation?
  private var downloadURL: String?
  private var activeDownloads: [ObjectIdentifier: WKDownload] = [:]
  init(original: WKNavigationDelegate?, privateMode: Bool, message: @escaping (String) -> Void,
    navigationSettled: @escaping (String) -> Void) {
    self.original = original; self.privateMode = privateMode; self.message = message
    self.navigationSettled = navigationSettled
  }
  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (original?.responds(to: selector) ?? false)
  }
  override func forwardingTarget(for selector: Selector!) -> Any? {
    if original?.responds(to: selector) == true { return original }
    return super.forwardingTarget(for: selector)
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    currentNavigation = navigation
    downloadNavigation = nil; downloadURL = nil
    original?.webView?(webView, didStartProvisionalNavigation: navigation)
  }
  private func consumeDownloadInterruption(_ navigation: WKNavigation?, error: Error) -> Bool {
    let failure = error as NSError
    guard let expected = downloadNavigation, let navigation = navigation,
      expected === navigation, failure.domain == "WebKitErrorDomain", failure.code == 102 else { return false }
    if let url = downloadURL { navigationSettled(url) }
    downloadNavigation = nil; downloadURL = nil
    return true
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if !consumeDownloadInterruption(navigation, error: error) {
      original?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if !consumeDownloadInterruption(navigation, error: error) {
      original?.webView?(webView, didFail: navigation, withError: error)
    }
  }
  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    // The upstream Dart HTTP-error callback omits frame identity. Do not turn
    // an embedded sign-in/ad frame's HTTP failure into a full-page error.
    // Navigation-action, TLS, and WebKit origin policies still apply normally.
    guard response.isForMainFrame else { decisionHandler(.allow); return }
    let attachment = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") == true
    guard attachment || !response.canShowMIMEType else {
      if let original = original, original.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:")) {
        original.webView?(webView, decidePolicyFor: response, decisionHandler: decisionHandler)
      } else { decisionHandler(.allow) }
      return
    }
    guard ["https", "http"].contains(response.response.url?.scheme ?? "") else { decisionHandler(.cancel); return }
    guard let presenter = webView.window?.rootViewController else { decisionHandler(.cancel); return }
    let alert = UIAlertController(title: "Download file?",
      message: (response.response.url?.host ?? "Website") + (privateMode ? "\nDownloaded files remain after closing private tabs." : ""), preferredStyle: .alert)
    let initiatingNavigation = currentNavigation
    let attemptedURL = response.response.url?.absoluteString ?? ""
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
      guard let self = self, self.currentNavigation === initiatingNavigation else {
        decisionHandler(.cancel); return
      }
      self.downloadNavigation = initiatingNavigation
      self.downloadURL = attemptedURL
      decisionHandler(.cancel)
      self.navigationSettled(attemptedURL)
    })
    alert.addAction(UIAlertAction(title: "Download", style: .default) { [weak self, weak webView] _ in
      guard let self = self, webView?.window != nil,
        self.currentNavigation === initiatingNavigation else { decisionHandler(.cancel); return }
      self.downloadNavigation = initiatingNavigation
      self.downloadURL = attemptedURL
      decisionHandler(.download)
    })
    var top = presenter
    while let presented = top.presentedViewController { top = presented }
    top.present(alert, animated: true)
  }
  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    activeDownloads[ObjectIdentifier(download)] = download; download.delegate = self
    if let url = navigationResponse.response.url?.absoluteString { navigationSettled(url) }
  }
  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
    let safe = String(suggestedFilename.unicodeScalars.map {
      CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._ -")).contains($0) ? Character($0) : "_"
    }.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    do {
      let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      var destination = folder.appendingPathComponent(safe.isEmpty ? "download" : safe)
      if FileManager.default.fileExists(atPath: destination.path) {
        destination = folder.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + (safe.isEmpty ? "download" : safe))
      }
      completionHandler(destination)
    } catch { completionHandler(nil); message("The download could not be saved.") }
  }
  func downloadDidFinish(_ download: WKDownload) {
    activeDownloads.removeValue(forKey: ObjectIdentifier(download))
    message("Download complete. Find it in Files → Wingman Browser → Downloads.")
  }
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    activeDownloads.removeValue(forKey: ObjectIdentifier(download)); message("The download failed. Please try again.")
  }
}
