import 'package:flutter/material.dart';
import 'package:flutter_push_plus/flutter_push_plus.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// App 被杀时点了「拒绝」：在后台 isolate 执行，不拉起界面。
@pragma('vm:entry-point')
Future<void> onBackgroundAction(PushMessage message) async =>
    debugPrint('background action: ${message.actionId} ${message.data}');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const HomePage(),
      routes: {'/detail': (_) => const DetailPage()},
    ),
  );
  await FlutterPushPlus.init(
    // 拿到/轮换令牌：实际项目里注册到自己的服务端
    onToken: (token) => debugPrint('push token: $token'),
    // App 在前台收到远程推送（默认同时弹横幅）
    onMessage: (message) => debugPrint('push message: $message'),
    // 点了通知或按钮：远程、本地统一走这里
    onOpen: (message) => navigatorKey.currentState?.pushNamed(
      message.data['page'] as String? ?? '/detail',
      arguments: message,
    ),
    onBackgroundAction: onBackgroundAction,
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = '';

  void _show(String text) => setState(() => _status = text);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_push_plus')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: () async =>
              _show('授权：${await FlutterPushPlus.requestPermission()}'),
          child: const Text('1. 申请通知权限'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async =>
              _show('令牌：${await FlutterPushPlus.getToken() ?? '暂未拿到'}'),
          child: const Text('2. 查看推送令牌'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => FlutterPushPlus.showNotification(
            id: 1,
            title: '张三',
            body: '晚上一起吃饭吗？点我打开详情',
            data: {'page': '/detail', 'conversationId': 'c42', 'unread': 3},
          ),
          child: const Text('3. 弹一条本地通知'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => FlutterPushPlus.showNotification(
            id: 2,
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
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: FlutterPushPlus.openNotificationSettings,
          child: const Text('通知被关了？去系统设置打开'),
        ),
        const SizedBox(height: 16),
        SelectableText(_status),
      ],
    ),
  );
}

/// 通知点进来的落地页：展示收到的消息。
class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final message = ModalRoute.of(context)!.settings.arguments as PushMessage?;
    return Scaffold(
      appBar: AppBar(title: const Text('从通知打开')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('source'),
            subtitle: Text('${message?.source.name}'),
          ),
          ListTile(
            title: const Text('actionId'),
            subtitle: Text('${message?.actionId}'),
          ),
          for (final e
              in message?.data.entries ?? const <MapEntry<String, Object?>>[])
            ListTile(
              title: Text(e.key),
              subtitle: Text('${e.value} (${e.value.runtimeType})'),
            ),
        ],
      ),
    );
  }
}
