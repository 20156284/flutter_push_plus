import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统来电界面上用户或系统触发的动作；[cancel] 是服务端 CANCEL 推送的收尾。
enum PushVoipAction { accept, decline, end, timeout, cancel }

/// 一通系统来电。[callId] 是服务端的通话标识，系统侧 UUID 由它派生，见 [uuid]。
@immutable
class PushVoipCall {
  const PushVoipCall({
    required this.callId,
    this.callerName = '',
    this.callerId = '',
    this.hasVideo = false,
    this.accepted = false,
    this.extra = const {},
  });

  final String callId;
  final String callerName;
  final String callerId;
  final bool hasVideo;

  /// 仅 [PushVoip.activeCalls] 有意义：用户是否已在系统界面接听。
  final bool accepted;

  /// 原样带回来电推送里的其余字段（`roomId`、`callerAvatar` 等）。
  final Map<String, Object?> extra;

  /// 系统侧 UUID（小写），事件里的 `uuid` 与它对应。
  String uuid() => PushVoip.uuidOf(callId);
}

/// [PushVoip.events] 的事件。
sealed class PushVoipEvent {
  const PushVoipEvent();
}

/// 用户在系统界面接听、拒绝、结束，或振铃超时、服务端取消。
final class PushVoipActionEvent extends PushVoipEvent {
  const PushVoipActionEvent(this.uuid, this.action);

  final String uuid;
  final PushVoipAction action;
}

/// 收到 VoIP 来电推送并已上报系统来电；App 活着但信令已断时靠它拿到来电数据。
final class PushVoipIncomingEvent extends PushVoipEvent {
  const PushVoipIncomingEvent(this.call);

  final PushVoipCall call;
}

/// 用户在系统通话界面切换静音。
final class PushVoipMuteEvent extends PushVoipEvent {
  const PushVoipMuteEvent(this.uuid, {required this.muted});

  final String uuid;
  final bool muted;
}

/// VoIP 令牌变化；失效时为 null。
final class PushVoipTokenEvent extends PushVoipEvent {
  const PushVoipTokenEvent(this.token);

  final String? token;
}

/// iOS 系统来电（PushKit + CallKit）。宿主只需在 Info.plist 的 `UIBackgroundModes` 加 `voip`；
/// 没加、非 iOS、Web 上所有方法都安全返回空结果。
class PushVoip {
  PushVoip._();

  static const _channel = MethodChannel('flutter_push_plus/voip');

  /// RFC 4122 的 DNS 命名空间。
  static const _namespace = <int>[
    0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, //
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
  ];

  static final _controller = StreamController<PushVoipEvent>.broadcast(
    onListen: () => _channel.setMethodCallHandler(_handle),
  );

  static bool _supported() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 系统界面的动作、静音与令牌变化；没人监听期间的事件不缓存，冷启动请用 [activeCalls]、[takeDeclined] 接回。
  static Stream<PushVoipEvent> events() => _controller.stream;

  /// 当前 VoIP 令牌，交给服务端发 VoIP 推送；还没拿到时为 null。
  static Future<String?> getToken() async {
    if (!_supported()) return null;
    return switch (await _channel.invokeMethod<Object?>('getToken')) {
      final String token => token,
      _ => null,
    };
  }

  /// 上报一通来电并弹出系统界面；系统拒绝（勿扰、拦截）为 false；同一通已在响算成功，返回 true。
  static Future<bool> reportIncoming(PushVoipCall call) async {
    if (!_supported()) return false;
    final reported = await _channel.invokeMethod<Object?>('reportIncoming', {
      'callId': call.callId,
      'callerName': call.callerName,
      'callerId': call.callerId,
      'hasVideo': call.hasVideo,
      'extra': call.extra,
    });
    return reported == true;
  }

  /// 结束这通来电或通话（对端取消、挂断等），不会再触发拒绝事件；系统里没有它也无妨。
  static Future<void> end(String uuid) async {
    if (!_supported()) return;
    await _channel.invokeMethod<Object?>('end', {'uuid': uuid});
  }

  /// 告知系统这通电话已接通，响铃随之停止；已接通或已结束则忽略。
  static Future<void> markConnected(String uuid) async {
    if (!_supported()) return;
    await _channel.invokeMethod<Object?>('connected', {'uuid': uuid});
  }

  /// 把 App 内的静音状态同步到系统通话界面。
  static Future<void> setMuted(String uuid, {required bool muted}) async {
    if (!_supported()) return;
    await _channel.invokeMethod<Object?>('setMuted', {
      'uuid': uuid,
      'muted': muted,
    });
  }

  /// 系统里仍挂着的来电，冷启动时用来接回用户已点的接听。
  static Future<List<PushVoipCall>> activeCalls() async {
    if (!_supported()) return const [];
    return _calls(await _channel.invokeMethod<Object?>('activeCalls'));
  }

  static List<PushVoipCall> _calls(Object? list) => [
    if (list is List)
      for (final item in list)
        if (item is Map) _call(item.cast<Object?, Object?>()),
  ];

  /// 取走并清空 App 被杀期间用户在系统界面拒绝的通话（落盘 90 秒内有效）。
  static Future<List<PushVoipCall>> takeDeclined() async {
    if (!_supported()) return const [];
    return _calls(await _channel.invokeMethod<Object?>('takeDeclined'));
  }

  /// 由服务端 callId 派生系统 UUID（RFC 4122 v5，DNS 命名空间，小写），与原生同算法。
  static String uuidOf(String callId) {
    final bytes = sha1
        .convert([..._namespace, ...utf8.encode(callId)])
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static PushVoipCall _call(Map<Object?, Object?> map) {
    final extra = switch (map['extra']) {
      final Map<Object?, Object?> m => {
        for (final e in m.entries)
          if (e.key is String) e.key! as String: e.value,
      },
      _ => <String, Object?>{},
    };
    return PushVoipCall(
      callId: extra['callId'] is String ? extra['callId']! as String : '',
      callerName: map['callerName'] is String ? map['callerName']! as String : '',
      callerId: map['callerId'] is String ? map['callerId']! as String : '',
      hasVideo: map['hasVideo'] == true,
      accepted: map['accepted'] == true,
      extra: extra,
    );
  }

  static Future<Object?> _handle(MethodCall call) async {
    final event = switch (call.method) {
      'token' => PushVoipTokenEvent(
        call.arguments is String ? call.arguments as String : null,
      ),
      'event' => _event(call.arguments),
      _ => null,
    };
    if (event != null) _controller.add(event);
    return null;
  }

  static PushVoipEvent? _event(Object? args) {
    if (args is! Map || args['uuid'] is! String) return null;
    final uuid = args['uuid']! as String;
    return switch (args['type']) {
      'incoming' => PushVoipIncomingEvent(_call(args.cast<Object?, Object?>())),
      'mute' => PushVoipMuteEvent(uuid, muted: args['muted'] == true),
      'action' => switch (PushVoipAction.values.asNameMap()[args['action']]) {
        final PushVoipAction action => PushVoipActionEvent(uuid, action),
        _ => null,
      },
      _ => null,
    };
  }
}
