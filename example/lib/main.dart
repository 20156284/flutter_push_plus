import 'package:flutter/material.dart';
import 'package:flutter_push_plus/flutter_push_plus.dart';

void main() => runApp(const MaterialApp(home: DemoPage()));

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _log = <String>[];

  void _add(String line) => setState(() => _log.insert(0, line));

  @override
  void initState() {
    super.initState();
    FlutterPushPlus.init(
      onOpen: (data) => _add('open: $data'),
      onToken: (token) => _add('token: $token'),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('flutter_push_plus')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton(
          onPressed: () async =>
              _add('permission: ${await FlutterPushPlus.requestPermission()}'),
          child: const Text('Request permission'),
        ),
        FilledButton(
          onPressed: () async =>
              _add('token: ${await FlutterPushPlus.getToken()}'),
          child: const Text('Get token'),
        ),
        FilledButton(
          onPressed: () => FlutterPushPlus.showLocal(
            id: 1,
            title: 'Hello',
            body: 'Tap me',
            payload: {'page': '/chat/1'},
          ),
          child: const Text('Show local notification'),
        ),
        ..._log.map(Text.new),
      ],
    ),
  );
}
