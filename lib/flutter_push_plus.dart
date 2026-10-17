import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 设备在某个推送通道下的令牌，原样交给服务端定向推送。
@immutable
class PushToken {
  const PushToken(this.channel, this.token);

  /// APNS / FCM（后续：HUAWEI / XIAOMI / OPPO / VIVO / HONOR）
  final String channel;
  final String token;

  @override
  String toString() => 'PushToken($channel, $token)';
}

/// 不放 google-services.json 时用这四项初始化 Firebase（取自 Firebase 控制台的安卓应用）。
@immutable
class FcmOptions {
  const FcmOptions({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.senderId,
  });

  final String apiKey;
  final String appId;
  final String projectId;
  final String senderId;

  Map<String, String> toMap() => {
    'apiKey': apiKey,
    'appId': appId,
    'projectId': projectId,
    'senderId': senderId,
  };
}

/// 远程推送、本地通知、点击跳转的统一入口。
///
/// 远程推送和本地通知被点击都回调 [init] 的 `onOpen`，参数是推送的自定义字段；
/// 冷启动时点的那条也会在 `init` 里补发，不会丢。
class FlutterPushPlus {
  FlutterPushPlus._();

  static const _channel = MethodChannel('flutter_push_plus');
  static final _local = FlutterLocalNotificationsPlugin();

  static ValueChanged<Map<String, Object?>>? _onOpen;
  static ValueChanged<PushToken>? _onToken;

  /// [localIcon] 是安卓本地通知的小图标（drawable/mipmap 资源名）；
  /// 宿主已自行初始化 flutter_local_notifications 时传 `local: false`，免得抢走它的点击回调。
  static Future<void> init({
    required ValueChanged<Map<String, Object?>> onOpen,
    ValueChanged<PushToken>? onToken,
    FcmOptions? fcm,
    bool local = true,
    String localIcon = '@mipmap/ic_launcher',
  }) async {
    if (kIsWeb) return;
    _onOpen = onOpen;
    _onToken = onToken;
    _channel.setMethodCallHandler(_handle);
    await _channel.invokeMethod<void>('init', fcm?.toMap());
    final launch = await _channel.invokeMapMethod<String, Object?>(
      'takeLaunchOpen',
    );
    if (launch != null) onOpen(launch);
    if (!local) return;
    await _local.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(localIcon),
        iOS: const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => _openLocal(r.payload),
    );
    final details = await _local.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      _openLocal(details!.notificationResponse?.payload);
    }
  }

  /// 当前通道令牌；还没拿到（iOS 首装、安卓未配 FCM）时为空，拿到后经 `onToken` 通知。
  static Future<PushToken?> getToken() async {
    final map = await _channel.invokeMapMethod<String, String>('getToken');
    return map == null ? null : PushToken(map['channel']!, map['token']!);
  }

  /// 申请通知权限（iOS 提醒/角标/声音，安卓 13+ POST_NOTIFICATIONS）。
  static Future<bool> requestPermission() async {
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.iOS =>
        await _local
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true),
      TargetPlatform.android =>
        await _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      _ => false,
    };
    return granted ?? false;
  }

  /// 弹一条本地通知；[payload] 在被点击时原样回到 `onOpen`。
  /// [channelId]/[channelName] 是安卓通知渠道，用户可在系统设置里按渠道开关。
  static Future<void> showLocal({
    required int id,
    String? title,
    String? body,
    Map<String, Object?> payload = const {},
    String channelId = 'default',
    String channelName = 'Notifications',
    String? icon,
    int? badge,
  }) => _local.show(
    id: id,
    title: title,
    body: body,
    payload: jsonEncode(payload),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        icon: icon,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(badgeNumber: badge),
    ),
  );

  static Future<void> cancelLocal(int id) => _local.cancel(id: id);

  static Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>();
    switch (call.method) {
      case 'token':
        _onToken?.call(
          PushToken(args!['channel']! as String, args['token']! as String),
        );
      case 'open':
        _onOpen?.call(args ?? const {});
        // 告诉原生已处理，否则它会留给下次 takeLaunchOpen
        return true;
    }
    return null;
  }

  static void _openLocal(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final decoded = jsonDecode(payload);
    _onOpen?.call(decoded is Map ? decoded.cast<String, Object?>() : const {});
  }
}
