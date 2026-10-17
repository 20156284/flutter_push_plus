import Flutter
import UIKit
import UserNotifications

/// iOS 端：APNs 令牌与推送点击。宿主 AppDelegate 需设 `UNUserNotificationCenter.current().delegate = self`，
/// FlutterAppDelegate 才会把通知回调转给插件。
public class FlutterPushPlusPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var token: String?
  /// 冷启动点推送时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。
  private var pendingOpen: [AnyHashable: Any]?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_push_plus", binaryMessenger: registrar.messenger())
    let instance = FlutterPushPlusPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      UIApplication.shared.registerForRemoteNotifications()
      result(nil)
    case "getToken":
      result(token.map { ["channel": "APNS", "token": $0] })
    case "takeLaunchOpen":
      result(pendingOpen)
      pendingOpen = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    token = hex
    channel.invokeMethod("token", arguments: ["channel": "APNS", "token": hex])
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // 本地通知留给 flutter_local_notifications 处理
    guard response.notification.request.trigger is UNPushNotificationTrigger else { return }
    let userInfo = response.notification.request.content.userInfo
    channel.invokeMethod("open", arguments: userInfo) { [weak self] handled in
      if handled as? Bool != true { self?.pendingOpen = userInfo }
    }
    completionHandler()
  }
}
