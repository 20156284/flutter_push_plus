# flutter_push_plus

一套接口管住远程推送、本地通知和点击跳转。插件只负责拿令牌、弹通知、回传点击，
**不绑定任何后端**：令牌怎么注册、推送怎么发由宿主 App 决定。

| 能力 | iOS | Android |
|---|---|---|
| 远程推送令牌 | APNs | FCM（华为/小米/OPPO/vivo/荣耀 待接） |
| 本地通知 | ✅ | ✅ |
| 点击回调（含冷启动） | ✅ | ✅ |

## 安装

```yaml
dependencies:
  flutter_push_plus:
    git:
      url: git@github.com:20156284/flutter_push_plus.git
      ref: v0.1.0
```

## 使用

```dart
await FlutterPushPlus.init(
  // 远程推送、本地通知被点都走这里，参数是推送的自定义字段 / showLocal 的 payload
  onOpen: (data) => router.go(data['page'] as String? ?? '/'),
  // 令牌首次拿到或轮换时回调，交给自己的服务端注册
  onToken: (t) => api.registerDevice(channel: t.channel, token: t.token),
  // 安卓 FCM：不放 google-services.json 时直接填这四项；都不给则不启用 FCM
  fcm: const FcmOptions(apiKey: '...', appId: '...', projectId: '...', senderId: '...'),
);

await FlutterPushPlus.requestPermission();
final token = await FlutterPushPlus.getToken(); // PushToken(channel, token)，可能为空

await FlutterPushPlus.showLocal(
  id: 1,
  title: '新消息',
  body: '你有一条新消息',
  payload: {'page': '/chat/123'},
  icon: 'ic_notify', // 安卓小图标资源名，默认用 init 的 localIcon
  badge: 3,          // iOS 角标
);
```

宿主已经自己初始化了 `flutter_local_notifications` 时，`init(local: false)`，只用远程推送部分。

## 平台配置

### iOS

1. Xcode → Signing & Capabilities 加 **Push Notifications**（会写入 `aps-environment`）。
2. `AppDelegate` 里设通知中心代理，FlutterAppDelegate 才会把点击转给插件：

```swift
UNUserNotificationCenter.current().delegate = self
```

服务端用 APNs Auth Key（.p8 + Key ID + Team ID）推送；Debug 包走沙箱环境。

### Android

FCM 二选一：
- 放 `android/app/google-services.json` 并接入 `com.google.gms.google-services` 插件；或
- 在 `init` 里传 `FcmOptions`（Firebase 控制台 → 项目设置 → 你的安卓应用）。

本地通知依赖 `flutter_local_notifications`，宿主 `android/app/build.gradle.kts` 需开启 desugaring：

```kotlin
android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
```

推送里的 `data` 字段在点击后原样出现在 `onOpen` 里（`google.*` / `gcm.*` 系统字段已去掉）。

## 路线

- [ ] 厂商通道：华为 HMS、荣耀、小米、OPPO、vivo（AppID/AppKey 走 `manifestPlaceholders`）
- [ ] 前台收到远程推送时的展示策略
