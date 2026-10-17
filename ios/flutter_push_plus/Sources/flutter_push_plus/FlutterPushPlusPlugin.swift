import Flutter
import UIKit
import UserNotifications

/// iOS 端：APNs 令牌、远程推送的前台展示与点击；本地通知由 flutter_local_notifications 处理。
public class FlutterPushPlusPlugin: NSObject, FlutterPlugin {
  private static let backgroundKey = "flutter_push_plus.backgroundHandle"
  private let channel: FlutterMethodChannel
  private var token: String?
  private var showInForeground = true
  /// 冷启动点推送时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。
  private var pendingOpen: [String: Any]?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_push_plus", binaryMessenger: registrar.messenger())
    let instance = FlutterPushPlusPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    // 宿主没设通知中心代理时替它设上，FlutterAppDelegate 会把回调转给各插件，免得宿主改原生代码
    let center = UNUserNotificationCenter.current()
    if center.delegate == nil, let app = UIApplication.shared.delegate as? UNUserNotificationCenterDelegate {
      center.delegate = app
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      let args = call.arguments as? [String: Any]
      showInForeground = args?["showInForeground"] as? Bool ?? true
      UserDefaults.standard.set(args?["backgroundHandle"] as? NSNumber, forKey: Self.backgroundKey)
      UIApplication.shared.registerForRemoteNotifications()
      result(nil)
    case "getToken":
      result(token.map { ["channel": "APNS", "token": $0] })
    case "takeLaunchOpen":
      result(pendingOpen)
      pendingOpen = nil
    case "getBackgroundHandle":
      result(UserDefaults.standard.object(forKey: Self.backgroundKey))
    case "openNotificationSettings":
      var url = UIApplication.openSettingsURLString
      if #available(iOS 16.0, *) { url = UIApplication.openNotificationSettingsURLString }
      UIApplication.shared.open(URL(string: url)!)
      result(nil)
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

  /// 自定义字段和 aps 平级，去掉 aps 就是 data。
  private static func message(_ notification: UNNotification) -> [String: Any] {
    let content = notification.request.content
    var data: [String: Any] = [:]
    for (key, value) in content.userInfo where key as? String != "aps" {
      if let key = key as? String { data[key] = value }
    }
    return ["title": content.title, "body": content.body, "data": data]
  }

  /// 前台收到远程推送：交给 Dart 的 onMessage，并按 showInForeground 决定是否弹横幅。
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // 本地通知留给 flutter_local_notifications；两边都调完成回调会崩
    guard notification.request.trigger is UNPushNotificationTrigger else { return }
    channel.invokeMethod("message", arguments: Self.message(notification))
    completionHandler(showInForeground ? [.banner, .list, .sound, .badge] : [])
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard response.notification.request.trigger is UNPushNotificationTrigger else { return }
    let open = Self.message(response.notification)
    channel.invokeMethod("open", arguments: open) { [weak self] handled in
      if handled as? Bool != true { self?.pendingOpen = open }
    }
    completionHandler()
  }
}
