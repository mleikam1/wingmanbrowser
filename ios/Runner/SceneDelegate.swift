import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyWindow: UIWindow?
  var privacyShieldVisible: Bool { privacyWindow?.isHidden == false }

  private func cover(_ scene: UIScene) {
    guard privacyWindow == nil, let scene = scene as? UIWindowScene else { return }
    let cover = UIWindow(windowScene: scene)
    cover.windowLevel = .alert + 1
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    let label = UILabel()
    label.text = "Wingman Browser"
    label.font = .preferredFont(forTextStyle: .headline)
    label.textColor = .label
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
    ])
    cover.rootViewController = controller
    cover.isUserInteractionEnabled = false
    cover.isHidden = false
    privacyWindow = cover
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    cover(scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    cover(scene)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyWindow?.isHidden = true
    privacyWindow = nil
  }

  #if DEBUG
  func setPrivacyShieldForTesting(_ scene: UIScene, visible: Bool) {
    if visible { cover(scene) }
    else { privacyWindow?.isHidden = true; privacyWindow = nil }
  }
  #endif

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts { AppDelegate.receive(context.url) }
    for activity in connectionOptions.userActivities {
      if let url = activity.webpageURL { AppDelegate.receive(url) }
    }
  }
  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    for context in contexts { AppDelegate.receive(context.url) }
  }
  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL { AppDelegate.receive(url) }
  }
}
