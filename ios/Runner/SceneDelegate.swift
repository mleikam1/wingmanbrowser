import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
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
