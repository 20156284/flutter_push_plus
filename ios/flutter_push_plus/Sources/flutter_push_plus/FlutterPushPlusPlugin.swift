import Flutter
import UIKit
import UserNotifications

/// iOS 端：APNs 令牌、远程推送的前台展示与点击；本地通知由 flutter_local_notifications 处理。
public class FlutterPushPlusPlugin: NSObject, FlutterPlugin {
  private static let backgroundKey = "flutter_push_plus.backgroundHandle"
  /// 后台按钮会另起引擎再注册一遍插件，只让最先注册的引擎接应用代理，否则完成回调被调两次会崩。宿主须在启动时同步注册主引擎。
  private static var delegateRegistered = false
  private let channel: FlutterMethodChannel
  private var token: String?
  /// init 之前不弹，与安卓一致。
  private var showInForeground = false
  /// 冷启动点推送时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。
  private var pendingOpen: [String: Any?]?

  /// 令牌环境，进程内只算一次：模拟器与开发描述文件为 sandbox，无描述文件（App Store、TestFlight）为 production，解析失败或 iOS 包跑在 Mac 上为 nil。
  private static let environment: String? = {
    #if targetEnvironment(simulator)
    return "sandbox"
    #else
    if ProcessInfo.processInfo.isiOSAppOnMac { return nil }
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
      return "production"
    }
    return apsEnvironment(provision: try? Data(contentsOf: url))
    #endif
  }()

  /// 描述文件是 CMS 签名包，内嵌的 XML plist 夹在明文里，截出来再读 `aps-environment`：development → sandbox，production → production，其余 nil。
  static func apsEnvironment(provision: Data?) -> String? {
    guard let provision, let start = provision.range(of: Data("<?xml".utf8)),
      let end = provision.range(of: Data("</plist>".utf8), in: start.upperBound..<provision.endIndex)
    else { return nil }
    let plist = try? PropertyListSerialization.propertyList(
      from: provision[start.lowerBound..<end.upperBound], options: [], format: nil)
    let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any]
    switch entitlements?["aps-environment"] as? String {
    case "development": return "sandbox"
    case "production": return "production"
    default: return nil
    }
  }

  private func tokenArguments(_ token: String) -> [String: Any?] {
    ["channel": "APNS", "token": token, "environment": Self.environment]
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_push_plus", binaryMessenger: registrar.messenger())
    let instance = FlutterPushPlusPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    guard !delegateRegistered else { return }
    delegateRegistered = true
    registrar.addApplicationDelegate(instance)
    PushPlusVoip.start(messenger: registrar.messenger())
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
      result(token.map(tokenArguments))
    case "takeLaunchOpen":
      result(pendingOpen)
      pendingOpen = nil
    case "getBackgroundHandle":
      result(UserDefaults.standard.object(forKey: Self.backgroundKey))
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
    channel.invokeMethod("token", arguments: tokenArguments(hex))
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // 多为没开 Push Notifications 能力或模拟器不支持
    NSLog("flutter_push_plus: APNs register failed: %@", error.localizedDescription)
  }

  /// 自定义字段和 aps 平级，去掉 aps 就是 data。
  private static func message(_ notification: UNNotification) -> [String: Any?] {
    let content = notification.request.content
    var data = content.userInfo as? [String: Any] ?? [:]
    data["aps"] = nil
    // 与安卓一致：没有标题正文时给 nil 而不是空串
    return [
      "title": content.title.isEmpty ? nil : content.title,
      "body": content.body.isEmpty ? nil : content.body,
      "data": data,
    ]
  }

  /// 前台收到远程推送：交给 Dart 的 onMessage，并按 showInForeground 决定是否弹横幅。
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // 非远程推送不接手，由 flutter_local_notifications 或发通知的插件处理；重复调完成回调会崩
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
    var open = Self.message(response.notification)
    if response.actionIdentifier != UNNotificationDefaultActionIdentifier {
      open["actionId"] = response.actionIdentifier
    }
    channel.invokeMethod("open", arguments: open) { [weak self, open] handled in
      if handled as? Bool != true { self?.pendingOpen = open }
    }
    completionHandler()
  }
}
