import 'package:flutter/material.dart';
import 'package:flutter_push_plus/flutter_push_plus.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
    // 点了通知：带 page 字段就跳过去，并把整包字段传给目标页
    onOpen: (data) => navigatorKey.currentState?.pushNamed(
      data['page'] as String? ?? '/detail',
      arguments: data,
    ),
    // 实际项目里在这里把令牌注册到自己的服务端
    onToken: (token) => debugPrint('push token: $token'),
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
          onPressed: () => FlutterPushPlus.showLocal(
            id: 1,
            title: '张三',
            body: '晚上一起吃饭吗？点我打开详情',
            payload: {'page': '/detail', 'conversationId': 'c42'},
            badge: 1,
          ),
          child: const Text('3. 弹一条本地通知'),
        ),
        const SizedBox(height: 16),
        SelectableText(_status),
      ],
    ),
  );
}

/// 通知点进来的落地页：展示收到的自定义字段。
class DetailPage extends StatelessWidget {
  const DetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = ModalRoute.of(context)!.settings.arguments as Map? ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('从通知打开')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final e in data.entries)
            ListTile(title: Text('${e.key}'), subtitle: Text('${e.value}')),
        ],
      ),
    );
  }
}
