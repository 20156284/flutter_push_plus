# flutter_push_plus

一套接口管住 **远程推送 + 本地通知 + 点击跳转**。

插件只做三件事：拿推送令牌、弹本地通知、把「用户点了哪条通知」回传给你。
它**不绑定任何后端**：令牌注册到哪、推送怎么发，由你的 App 和服务端决定。

| 能力 | iOS | Android |
|---|---|---|
| 远程推送令牌 | APNs | FCM（华为/荣耀/小米/OPPO/vivo 待接） |
| 本地通知（图标/标题/内容/角标） | ✅ | ✅ |
| 点击回调（App 在前台、后台、被杀冷启动） | ✅ | ✅ |

---

## 目录

1. [安装](#1-安装)
2. [平台配置](#2-平台配置)
3. [五分钟接入](#3-五分钟接入)
4. [API 一览](#4-api-一览)
5. [服务端怎么发推送](#5-服务端怎么发推送)
6. [示例工程](#6-示例工程)
7. [常见问题](#7-常见问题)

---

## 1. 安装

`pubspec.yaml`：

```yaml
dependencies:
  flutter_push_plus:
    git:
      url: https://github.com/20156284/flutter_push_plus.git
      ref: v0.1.0
```

```bash
flutter pub get
```

## 2. 平台配置

### iOS

1. Xcode 打开 `ios/Runner.xcworkspace` → **Signing & Capabilities** → `+ Capability` → 加 **Push Notifications**。
2. `ios/Runner/AppDelegate.swift` 里设置通知中心代理（不设的话点通知收不到回调）：

```swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self   // ← 加这一行
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### Android

1. `android/app/build.gradle.kts` 开启 desugaring（本地通知库要求）：

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
```

2. FCM 配置**二选一**（都不配也能跑，只是安卓拿不到远程推送令牌）：
   - **方式 A（推荐，免改 gradle）**：在 `init` 里传 `FcmOptions`，四个值取自
     Firebase 控制台 → 项目设置 → 常规 → 你的安卓应用。
   - **方式 B**：把 `google-services.json` 放到 `android/app/`，并接入 `com.google.gms.google-services` 插件。

3. 通知小图标：把白色透明底的图标放到 `android/app/src/main/res/drawable/ic_notify.png`，
   `init(localIcon: '@drawable/ic_notify')` 即可；不传默认用 App 图标。

## 3. 五分钟接入

```dart
import 'package:flutter/material.dart';
import 'package:flutter_push_plus/flutter_push_plus.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterPushPlus.init(
    // ① 用户点了通知（远程或本地都走这里）→ 按自定义字段跳页面
    onOpen: (data) {
      final page = data['page'] as String?;
      if (page != null) navigatorKey.currentState?.pushNamed(page, arguments: data);
    },
    // ② 拿到/换了推送令牌 → 交给自己的服务端
    onToken: (token) => myApi.registerDevice(token.channel, token.token),
    // ③ 安卓 FCM（可选）
    fcm: const FcmOptions(
      apiKey: 'AIza...',
      appId: '1:1234567890:android:abcdef',
      projectId: 'my-project',
      senderId: '1234567890',
    ),
  );

  // ④ 申请通知权限（iOS 弹系统框；安卓 13+ 弹系统框，更低版本返回当前是否允许通知）
  await FlutterPushPlus.requestPermission();

  runApp(MaterialApp(navigatorKey: navigatorKey, /* routes: ... */));
}
```

弹一条本地通知，点了它同样会进 `onOpen`：

```dart
await FlutterPushPlus.showLocal(
  id: 1001,                                  // 同 id 会覆盖上一条
  title: '张三',
  body: '晚上一起吃饭吗？',
  payload: {'page': '/chat', 'conversationId': 'c42'},
  badge: 3,                                  // iOS 角标
);
```

> 冷启动（App 被杀后点通知拉起）时，`onOpen` 会在 `init` 里回调。
> 这时界面可能还没建好，建议先把 `data` 存起来，首页出来后再跳。

## 4. API 一览

| 方法 | 说明 |
|---|---|
| `init({onOpen, onToken, fcm, local, localIcon})` | 启动时调一次。`local: false` 表示你已自己初始化了 `flutter_local_notifications`，插件不接管本地通知 |
| `getToken()` | 返回 `PushToken(channel, token)`；还没拿到时为 `null`，拿到后会走 `onToken` |
| `requestPermission()` | 申请通知权限，返回是否授权 |
| `showLocal({id, title, body, payload, channelId, channelName, icon, badge})` | 弹本地通知；`payload` 点击时原样回到 `onOpen` |
| `cancelLocal(id)` | 撤掉某条本地通知 |

`PushToken.channel` 取值：`APNS`（iOS）、`FCM`（安卓）。服务端按它决定走哪家推送。

## 5. 服务端怎么发推送

插件只认推送里的**自定义字段**，字段名你和服务端自己约定（下面用 `page` 举例）。

**iOS（APNs）**：自定义字段和 `aps` 平级。`onOpen` 收到的是整个 payload（含 `aps`）。

```json
{
  "aps": { "alert": { "title": "张三", "body": "晚上一起吃饭吗？" }, "badge": 3, "sound": "default" },
  "page": "/chat",
  "conversationId": "c42"
}
```

服务端用 APNs Auth Key（`.p8` + Key ID + Team ID）发送；Debug 包要发到**沙箱**环境。

**Android（FCM HTTP v1）**：自定义字段放 `data`，值必须是字符串。`onOpen` 收到的就是 `data`。

```json
{
  "message": {
    "token": "<设备令牌>",
    "notification": { "title": "张三", "body": "晚上一起吃饭吗？" },
    "data": { "page": "/chat", "conversationId": "c42" }
  }
}
```

**本地调试**：iOS 模拟器可以不经服务器直接模拟一条推送：

```bash
xcrun simctl push booted <你的 bundle id> payload.json
```

## 6. 示例工程

`example/` 是一个可直接运行的演示：申请权限、看令牌、弹本地通知、点通知跳到详情页显示收到的字段。

```bash
cd example
flutter run
```

## 7. 常见问题

**iOS 点通知没反应？** 检查 `AppDelegate` 里有没有设 `UNUserNotificationCenter.current().delegate = self`。

**iOS 拿不到令牌？** 没加 Push Notifications 能力，或在不支持推送的模拟器上运行（Apple 芯片 Mac 上的 iOS 16+ 模拟器才支持）。

**安卓拿不到令牌？** 没配 FCM（见 2-Android-2），或设备没有 Google 服务（国行手机）——这类设备要等厂商通道。

**和项目里已有的 `flutter_local_notifications` 冲突？** 用 `init(local: false)`，本地通知继续走你原来的代码，插件只管远程推送。

**App 在前台时收到远程推送不弹横幅？** 当前版本前台不展示，一般前台走长连接，需要的话收到后自己 `showLocal`。

## 路线

- [ ] 厂商通道：华为 HMS、荣耀、小米、OPPO、vivo（AppID/AppKey 走 `manifestPlaceholders`）
- [ ] 前台收到远程推送时的展示策略

## License

MIT
