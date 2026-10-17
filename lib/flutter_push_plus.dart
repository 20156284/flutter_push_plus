import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'src/models.dart';

export 'src/models.dart';

/// 后台按钮回调：必须是顶层或静态函数，并加 `@pragma('vm:entry-point')`。
typedef PushBackgroundHandler = Future<void> Function(PushMessage message);

/// 远程推送、本地通知、点击跳转的统一入口：iOS 走 APNs，安卓按品牌走厂商通道、其余 FCM。
/// 后台/被杀时由系统通知栏展示；本地通知与前台推送由插件弹出，图标、渠道与远程推送一致。
class FlutterPushPlus {
  FlutterPushPlus._();

  static const _channel = MethodChannel('flutter_push_plus');
  static const _portName = 'flutter_push_plus.action';
  static final _local = FlutterLocalNotificationsPlugin();

  static ValueChanged<PushToken>? _onToken;
  static ValueChanged<PushMessage>? _onMessage;
  static ValueChanged<PushMessage>? _onOpen;
  static var _showInForeground = true;
  static var _defaultChannel = const PushNotificationChannel('push', 'Push');
  static final _channels = <String, PushNotificationChannel>{};
  static final _categories = <String, PushCategory>{};
  static ReceivePort? _actionPort;

  /// 启动推送，须在用户同意隐私政策之后调用。[onToken] 拿到/轮换令牌；[onMessage] 前台收到远程推送；
  /// [onOpen] 点了通知或按钮（远程、本地、冷启动都走这里）；[onBackgroundAction] App 被杀时点了不拉起 App 的按钮。
  static Future<void> init({
    ValueChanged<PushToken>? onToken,
    ValueChanged<PushMessage>? onMessage,
    ValueChanged<PushMessage>? onOpen,
    PushBackgroundHandler? onBackgroundAction,
    bool showInForeground = true,
    List<PushNotificationChannel> notificationChannels = const [],
    List<PushCategory> categories = const [],
  }) async {
    _onToken = onToken;
    _onMessage = onMessage;
    _onOpen = onOpen;
    _showInForeground = showInForeground;
    _categories
      ..clear()
      ..addEntries(categories.map((c) => MapEntry(c.id, c)));

    var icon = '@mipmap/ic_launcher';
    if (!kIsWeb) {
      _channel.setMethodCallHandler(_handle);
      final native = await _channel.invokeMapMethod<String, Object?>('init', {
        'showInForeground': showInForeground,
        'backgroundHandle': onBackgroundAction == null
            ? null
            : PluginUtilities.getCallbackHandle(
                onBackgroundAction,
              )?.toRawHandle(),
      });
      _defaultChannel = PushNotificationChannel(
        native?['channelId'] as String? ?? 'push',
        native?['channelName'] as String? ?? 'Push',
      );
      icon = native?['icon'] as String? ?? icon;
      _listenActions();
    }

    await _local.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(icon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            for (final c in categories)
              DarwinNotificationCategory(
                c.id,
                actions: [
                  for (final a in c.actions)
                    DarwinNotificationAction.plain(
                      a.id,
                      a.title,
                      options: {
                        if (a.foreground)
                          DarwinNotificationActionOption.foreground,
                        if (a.destructive)
                          DarwinNotificationActionOption.destructive,
                      },
                    ),
                ],
              ),
          ],
        ),
        web: const WebInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (r) => _onOpen?.call(_decode(r)),
      onDidReceiveBackgroundNotificationResponse: pushPlusBackgroundEntry,
    );
    for (final c in [_defaultChannel, ...notificationChannels]) {
      await createNotificationChannel(c);
    }

    // 冷启动：远程推送由原生先存着，本地通知由 flutter_local_notifications 记着
    if (!kIsWeb) {
      final remote = await _channel.invokeMapMethod<String, Object?>(
        'takeLaunchOpen',
      );
      if (remote != null) _onOpen?.call(_remote(remote));
    }
    final launch = await _local.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _onOpen?.call(_decode(response));
    }
  }

  /// 当前通道令牌；还没拿到时为 null，拿到后经 `onToken` 通知。Web 上恒为 null。
  static Future<PushToken?> getToken() async {
    if (kIsWeb) return null;
    final map = await _channel.invokeMapMethod<String, String>('getToken');
    return map == null ? null : PushToken(map['channel']!, map['token']!);
  }

  /// 当前通知权限状态；`notDetermined` 只有 Web 能区分，移动端未授权一律是 `denied`。
  static Future<PushPermission> getPermission() async {
    if (kIsWeb) {
      return switch (_web?.permissionStatus) {
        WebNotificationPermission.granted => PushPermission.granted,
        WebNotificationPermission.denied => PushPermission.denied,
        _ => PushPermission.notDetermined,
      };
    }
    final enabled = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => (await _ios?.checkPermissions())?.isEnabled,
      _ => await _android?.areNotificationsEnabled(),
    };
    return (enabled ?? false) ? PushPermission.granted : PushPermission.denied;
  }

  /// 申请通知权限：iOS、安卓 13+ 弹系统授权框；Web 必须在用户点击等手势里调用。
  static Future<bool> requestPermission() async {
    final granted = kIsWeb
        ? await _web?.requestNotificationsPermission()
        : switch (defaultTargetPlatform) {
            TargetPlatform.iOS => await _ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ),
            _ => await _android?.requestNotificationsPermission(),
          };
    return granted ?? false;
  }

  /// 打开本 App 的系统通知设置页：用户拒绝过授权，或 ColorOS、vivo 默认关了通知时引导去开。
  static Future<void> openNotificationSettings() async {
    if (!kIsWeb) await _channel.invokeMethod<void>('openNotificationSettings');
  }

  /// 弹通知，点击时 [data] 原样回到 `onOpen`（须可 JSON 序列化）。[channelId] 默认 `pushPlus.channelId`，
  /// [category] 引用 init 的按钮组；[silent] 不响不振；[ongoing]/[fullScreen] 仅安卓，[timeSensitive]/[badge] 仅 iOS。
  static Future<void> showNotification({
    required int id,
    String? title,
    String? body,
    Map<String, Object?> data = const {},
    String? channelId,
    String? category,
    bool silent = false,
    bool ongoing = false,
    bool fullScreen = false,
    bool timeSensitive = false,
    int? badge,
  }) => _show(
    id,
    PushMessage(source: PushSource.local, title: title, body: body, data: data),
    channelId: channelId,
    category: category,
    silent: silent,
    ongoing: ongoing,
    fullScreen: fullScreen,
    timeSensitive: timeSensitive,
    badge: badge,
  );

  static Future<void> cancelNotification(int id) => _local.cancel(id: id);

  static Future<void> cancelAllNotifications() => _local.cancelAll();

  /// 运行时新建安卓通知渠道（如用户关了声音，换一个静音渠道）；iOS、Web 无此概念，直接忽略。
  static Future<void> createNotificationChannel(
    PushNotificationChannel channel,
  ) async {
    _channels[channel.id] = channel;
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        channel.id,
        channel.name,
        importance: _importance(channel.importance),
        playSound: channel.sound,
        enableVibration: channel.vibrate,
      ),
    );
  }

  static Future<void> deleteNotificationChannel(String id) async {
    _channels.remove(id);
    await _android?.deleteNotificationChannel(channelId: id);
  }

  static Future<void> _show(
    int id,
    PushMessage message, {
    String? channelId,
    String? category,
    bool silent = false,
    bool ongoing = false,
    bool fullScreen = false,
    bool timeSensitive = false,
    int? badge,
  }) {
    assert(
      channelId == null || _channels.containsKey(channelId),
      '通知渠道 $channelId 未创建，先在 init(notificationChannels:) 或 createNotificationChannel 里建',
    );
    assert(
      category == null || _categories.containsKey(category),
      '按钮组 $category 未注册，先在 init(categories:) 里声明',
    );
    final channel = _channels[channelId] ?? _defaultChannel;
    return _local.show(
      id: id,
      title: message.title,
      body: message.body,
      payload: jsonEncode({
        's': message.source.name,
        't': message.title,
        'b': message.body,
        'd': message.data,
      }),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: _importance(channel.importance),
          priority: switch (channel.importance) {
            PushImportance.max => Priority.max,
            PushImportance.high => Priority.high,
            _ => Priority.defaultPriority,
          },
          playSound: channel.sound,
          enableVibration: channel.vibrate,
          silent: silent,
          ongoing: ongoing,
          autoCancel: !ongoing,
          fullScreenIntent: fullScreen,
          // 全屏通知按来电归类，勿扰模式下系统才会放行来电
          category: fullScreen
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          actions: [
            for (final a
                in _categories[category]?.actions ?? const <PushAction>[])
              AndroidNotificationAction(
                a.id,
                a.title,
                showsUserInterface: a.foreground,
                cancelNotification: true,
              ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: category,
          badgeNumber: badge,
          presentSound: !silent,
          interruptionLevel: timeSensitive
              ? InterruptionLevel.timeSensitive
              : null,
        ),
        // 同 id 原位替换时浏览器默认不再提醒，非静默要显式要求再提醒
        web: WebNotificationDetails(renotify: !silent),
      ),
    );
  }

  static Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'token':
        _onToken?.call(
          PushToken(args['channel']! as String, args['token']! as String),
        );
      case 'message':
        final message = _remote(args);
        _onMessage?.call(message);
        // 安卓前台收到 FCM/透传时系统不弹，由插件代弹；iOS 原生已按 showInForeground 处理
        if (_showInForeground &&
            defaultTargetPlatform == TargetPlatform.android &&
            (message.title != null || message.body != null)) {
          await _show(
            DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
            message,
          );
        }
      case 'open':
        _onOpen?.call(_remote(args));
        // 告诉原生已处理，否则它会留给下次 takeLaunchOpen
        return true;
    }
    return null;
  }

  /// 不拉起 App 的按钮在后台 isolate 回调；主 isolate 活着就转回去走 onOpen。
  static void _listenActions() {
    _actionPort?.close();
    IsolateNameServer.removePortNameMapping(_portName);
    _actionPort = ReceivePort()
      ..listen((msg) {
        final [payload, actionId, reply] = msg as List;
        (reply as SendPort).send(true);
        _onOpen?.call(_decodeJson(payload as String?, actionId as String?));
      });
    IsolateNameServer.registerPortWithName(_actionPort!.sendPort, _portName);
  }

  static PushMessage _remote(Map<String, Object?> args) => PushMessage(
    source: PushSource.remote,
    title: args['title'] as String?,
    body: args['body'] as String?,
    data: (args['data'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  static PushMessage _decode(NotificationResponse r) =>
      _decodeJson(r.payload, r.actionId);

  /// 不是本插件发的通知（如升级前留在通知栏的旧通知）原文放进 `data['payload']`，不能抛错。
  static PushMessage _decodeJson(String? payload, String? actionId) {
    if (payload == null || payload.isEmpty) {
      return PushMessage(source: PushSource.local, actionId: actionId);
    }
    final decoded = _tryDecode(payload);
    final map = decoded is Map && decoded.containsKey('s')
        ? decoded.cast<String, Object?>()
        : {
            'd': {'payload': payload},
          };
    return PushMessage(
      source: map['s'] == PushSource.remote.name
          ? PushSource.remote
          : PushSource.local,
      title: map['t'] as String?,
      body: map['b'] as String?,
      data: (map['d'] as Map?)?.cast<String, Object?>() ?? const {},
      actionId: actionId,
    );
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static Importance _importance(PushImportance i) => switch (i) {
    PushImportance.low => Importance.low,
    PushImportance.normal => Importance.defaultImportance,
    PushImportance.high => Importance.high,
    PushImportance.max => Importance.max,
  };

  static AndroidFlutterLocalNotificationsPlugin? get _android => _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  static IOSFlutterLocalNotificationsPlugin? get _ios => _local
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  static WebFlutterLocalNotificationsPlugin? get _web => kIsWeb
      ? _local
            .resolvePlatformSpecificImplementation<
              WebFlutterLocalNotificationsPlugin
            >()
      : null;
}

/// 插件内部使用：后台按钮的入口。主 isolate 活着就转交给 onOpen，否则调用 `onBackgroundAction`。
/// 主引擎被销毁而进程还在时端口映射不会自动删，所以要等回执，1 秒没回就当它不在。
@pragma('vm:entry-point')
Future<void> pushPlusBackgroundEntry(NotificationResponse response) async {
  final port = IsolateNameServer.lookupPortByName(FlutterPushPlus._portName);
  if (port != null) {
    final reply = ReceivePort();
    port.send([response.payload, response.actionId, reply.sendPort]);
    final alive = await reply.first.timeout(
      const Duration(seconds: 1),
      onTimeout: () => false,
    );
    reply.close();
    if (alive == true) return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final raw = await FlutterPushPlus._channel.invokeMethod<int>(
    'getBackgroundHandle',
  );
  if (raw == null) return;
  final handler = PluginUtilities.getCallbackFromHandle(
    CallbackHandle.fromRawHandle(raw),
  );
  if (handler is PushBackgroundHandler) {
    await handler(FlutterPushPlus._decode(response));
  }
}
