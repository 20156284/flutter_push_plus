import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 设备在某个推送通道下的令牌，原样交给服务端定向推送。
@immutable
class PushToken {
  const PushToken(this.channel, this.token);

  /// APNS / FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO，与服务端通道枚举一致
  final String channel;
  final String token;

  @override
  String toString() => 'PushToken($channel, $token)';
}

/// 远程推送、本地通知、点击跳转的统一入口。
///
/// 安卓按手机品牌自动选通道（华为/荣耀/小米/OPPO/vivo，其余走 FCM），各家 ID 写在宿主
/// `android/gradle.properties`；远程推送和本地通知被点击都回调 `onOpen`，冷启动那条也不会丢。
class FlutterPushPlus {
  FlutterPushPlus._();

  static const _channel = MethodChannel('flutter_push_plus');
  static final _local = FlutterLocalNotificationsPlugin();

  static ValueChanged<Map<String, Object?>>? _onOpen;
  static ValueChanged<PushToken>? _onToken;
  static ValueChanged<Map<String, Object?>>? _onMessage;
  static var _channelId = 'push';
  static var _channelName = 'Push';

  /// 须在用户同意隐私政策之后调用（小米、vivo 等合规要求）。
  /// [onMessage] 是 App 在前台时收到的远程推送；[showForeground] 为 true 时同时弹系统横幅。
  /// 宿主已自行初始化 flutter_local_notifications 时传 `local: false`，免得抢走它的点击回调。
  static Future<void> init({
    required ValueChanged<Map<String, Object?>> onOpen,
    ValueChanged<PushToken>? onToken,
    ValueChanged<Map<String, Object?>>? onMessage,
    bool showForeground = true,
    bool local = true,
    String localIcon = '@mipmap/ic_launcher',
  }) async {
    if (kIsWeb) return;
    _onOpen = onOpen;
    _onToken = onToken;
    _onMessage = onMessage;
    _channel.setMethodCallHandler(_handle);
    final channel = await _channel.invokeMapMethod<String, String>('init', {
      'showForeground': showForeground,
    });
    _channelId = channel?['channelId'] ?? _channelId;
    _channelName = channel?['channelName'] ?? _channelName;
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

  /// 打开本 App 的系统通知设置页；ColorOS、vivo 等新装默认关通知，拒绝过授权后只能引导去这里开。
  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  /// 弹一条本地通知；[payload] 在被点击时原样回到 `onOpen`。
  /// 安卓通知渠道默认用 gradle.properties 的 `pushPlus.channelId`，与远程推送同一个渠道。
  static Future<void> showLocal({
    required int id,
    String? title,
    String? body,
    Map<String, Object?> payload = const {},
    String? channelId,
    String? channelName,
    String? icon,
    int? badge,
  }) => _local.show(
    id: id,
    title: title,
    body: body,
    payload: jsonEncode(payload),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId ?? _channelId,
        channelName ?? _channelName,
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
      case 'message':
        _onMessage?.call(args ?? const {});
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
