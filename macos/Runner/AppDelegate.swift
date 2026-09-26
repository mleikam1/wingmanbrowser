import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static var browserBridge: BrowserNativeBridge?
  private var privacyCover: NSView?
  var privacyShieldVisible: Bool { privacyCover != nil }

  func setSensitive(_ value: Bool) {
    // All inactive windows are covered; this does not depend on a Dart hint.
    if !NSApp.isActive { cover() }
  }

  private func cover() {
    guard privacyCover == nil, let view = mainFlutterWindow?.contentView else { return }
    let cover = NSView(frame: view.bounds); cover.autoresizingMask = [.width, .height]
    cover.wantsLayer = true; cover.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let label = NSTextField(labelWithString: "Wingman Browser"); label.font = .systemFont(ofSize: 20, weight: .semibold)
    label.translatesAutoresizingMaskIntoConstraints = false; cover.addSubview(label)
    NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: cover.centerXAnchor), label.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
    view.addSubview(cover); privacyCover = cover
  }

  override func applicationWillResignActive(_ notification: Notification) {
    cover(); AppDelegate.browserBridge?.protectedBrowser.pauseAll()
    super.applicationWillResignActive(notification)
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    AppDelegate.browserBridge?.protectedBrowser.resume()
    privacyCover?.removeFromSuperview(); privacyCover = nil
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { AppDelegate.browserBridge?.receive(url) }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
