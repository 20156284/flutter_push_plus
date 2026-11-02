import 'package:flutter/material.dart';
import 'package:flutter_push_plus/flutter_push_plus.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

/// App 被杀时点了「拒绝」：在后台 isolate 执行，不拉起界面。
@pragma('vm:entry-point')
Future<void> _onBackgroundAction(PushMessage message) async =>
    debugPrint('background action: ${message.actionId} ${message.data}');

Future<void> main() async {
  runApp(MaterialApp(navigatorKey: _navigatorKey, home: const _HomePage()));
  // 实际项目须在用户同意隐私政策之后调用
  await FlutterPushPlus.init(
    // 拿到/轮换令牌：实际项目里注册到自己的服务端
    onToken: (token) => debugPrint('push token: $token'),
    // 收到远程推送（默认同时弹横幅）
    onMessage: (message) => debugPrint('push message: $message'),
    // 点了通知或按钮：远程、本地统一走这里；「拒绝」不跳页
    onOpen: (message) {
      if (message.actionId == 'reject') return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => _DetailPage(message)),
      );
    },
    onBackgroundAction: _onBackgroundAction,
    notificationChannels: const [
      PushNotificationChannel(
        'call',
        '来电',
        importance: PushImportance.max,
        sound: false,
      ),
    ],
    categories: const [
      PushCategory('call', [
        PushAction('reject', '拒绝', destructive: true),
        PushAction('accept', '接听', foreground: true),
      ]),
    ],
  );
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  static const _callId = 2;

  String _status = '';
  bool _busy = false;

  /// 权限申请连点会抛错，进行中直接返回。
  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      final text = await action();
      if (mounted) setState(() => _status = text);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_push_plus')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => _run(
              () async => '授权：${await FlutterPushPlus.requestPermission()}',
            ),
            child: const Text('1. 申请通知权限'),
          ),
          FilledButton(
            onPressed: () => _run(
              () async => '令牌：${await FlutterPushPlus.getToken() ?? '暂未拿到'}',
            ),
            child: const Text('2. 查看推送令牌'),
          ),
          FilledButton(
            onPressed: () => FlutterPushPlus.showNotification(
              id: 1,
              title: '张三',
              body: '晚上一起吃饭吗？点我打开详情',
              data: {'conversationId': 'c42', 'unread': 3},
            ),
            child: const Text('3. 弹一条本地通知'),
          ),
          FilledButton(
            onPressed: () => FlutterPushPlus.showNotification(
              id: _callId,
              title: '李四',
              body: '邀请你语音通话',
              data: {'callId': 'call-7'},
              category: 'call',
              channelId: 'call',
              ongoing: true,
              fullScreen: true,
            ),
            child: const Text('4. 带按钮的通知（来电）'),
          ),
          OutlinedButton(
            onPressed: () => FlutterPushPlus.cancelNotification(_callId),
            child: const Text('取消来电通知'),
          ),
          OutlinedButton(
            onPressed: FlutterPushPlus.openNotificationSettings,
            child: const Text('通知被关了？去系统设置打开'),
          ),
          SelectableText(_status),
        ],
      ),
    ),
  );
}

/// 通知点进来的落地页：展示收到的消息。
class _DetailPage extends StatelessWidget {
  const _DetailPage(this.message);

  final PushMessage message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('从通知打开')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (label, value) in [
          ('source', message.source.name),
          ('title', message.title ?? '（无）'),
          ('body', message.body ?? '（无）'),
          ('actionId', message.actionId ?? '（通知本体）'),
        ])
          ListTile(title: Text(label), subtitle: Text(value)),
        for (final MapEntry(:key, :value) in message.data.entries)
          ListTile(
            title: Text(key),
            subtitle: Text('$value (${value.runtimeType})'),
          ),
      ],
    ),
  );
}
