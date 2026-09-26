import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppDelegate.browserBridge = BrowserNativeBridge(registrar: flutterViewController.registrar(forPlugin: "WingmanBrowser"))
    self.minSize = NSSize(width: 720, height: 560)
    self.setContentSize(NSSize(width: 1280, height: 850))
    self.center()

    super.awakeFromNib()
  }
}
