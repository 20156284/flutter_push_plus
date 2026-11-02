import 'package:flutter/foundation.dart';

/// 消息从哪来：服务端远程推送，或本机 [FlutterPushPlus.showNotification]。
enum PushSource { remote, local }

/// 通知权限状态。
enum PushPermission { granted, denied, notDetermined }

/// 安卓通知渠道的重要性；`high` 及以上才会弹横幅。
enum PushImportance { low, normal, high, max }

/// APNs 令牌所属环境，由描述文件的 `aps-environment` 决定，与编译模式无关。
enum PushEnvironment { sandbox, production }

/// 设备在某个推送通道下的令牌，原样交给服务端定向推送。
@immutable
class PushToken {
  const PushToken(this.channel, this.token, {this.environment});

  /// APNS / FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO，与服务端通道枚举一致
  final String channel;
  final String token;

  /// 仅 iOS 有值；安卓与无法判定时为 null。
  final PushEnvironment? environment;

  @override
  bool operator ==(Object other) =>
      other is PushToken &&
      other.channel == channel &&
      other.token == token &&
      other.environment == environment;

  @override
  int get hashCode => Object.hash(channel, token, environment);

  @override
  String toString() => 'PushToken($channel, $token, $environment)';
}

/// 一条推送：远程和本地、到达和点击，统一是这个形状。
@immutable
class PushMessage {
  const PushMessage({
    required this.source,
    this.title,
    this.body,
    this.data = const {},
    this.actionId,
  });

  final PushSource source;

  /// 安卓远程推送被点击时系统不回传标题正文，为 null；只有 `data` 一定在。
  final String? title;
  final String? body;

  /// 服务端下发的自定义字段，或 [FlutterPushPlus.showNotification] 传入的 `data`。
  /// 远程推送的值安卓一律是字符串，iOS 保留 APNs 的 JSON 类型，服务端请统一发字符串。
  final Map<String, Object?> data;

  /// 点的是通知上的按钮时为按钮 id，点通知本体为 null。
  final String? actionId;

  @override
  String toString() =>
      'PushMessage(${source.name}, $title, $body, $data, action: $actionId)';
}

/// 安卓通知渠道。重要性、声音、振动在渠道建好后系统不让改，要变就换个 id 新建。
@immutable
class PushNotificationChannel {
  const PushNotificationChannel(
    this.id,
    this.name, {
    this.importance = PushImportance.high,
    this.sound = true,
    this.vibrate = true,
  });

  final String id;
  final String name;
  final PushImportance importance;
  final bool sound;
  final bool vibrate;
}

/// 通知上的按钮。[foreground] 为 true 时点了会拉起 App，否则在后台处理。
@immutable
class PushAction {
  const PushAction(
    this.id,
    this.title, {
    this.foreground = false,
    this.destructive = false,
  });

  final String id;
  final String title;
  final bool foreground;

  /// iOS 上显示为红色。
  final bool destructive;
}

/// 一组按钮，发通知时用 `category` 引用（iOS 要求启动时注册好）。
@immutable
class PushCategory {
  const PushCategory(this.id, this.actions);

  final String id;
  final List<PushAction> actions;
}
