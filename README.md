# flutter_push_plus

一套接口管住 **远程推送 + 本地通知 + 点击跳转**，安卓按手机品牌自动走厂商通道。

- **配置 + 一次调用**：按第 2 节配好各平台（主要是在 `android/gradle.properties` 填各家 ID），在 Dart 里调一次 `init`。
- **按需打包**：哪家没填 ID，哪家的 SDK 就不编进 APK，不会因为接了插件而臃肿。
- **统一模型**：远程推送、本地通知、到达、点击、按钮，全部是同一个 `PushMessage`（标题 / 正文 / data / 来源 / 按钮 id）。
- **统一回调**：令牌走 `onToken`，App 活着时收到的推送走 `onMessage`（各通道差异见第 5 节），用户点击（远程推送、本地通知、通知按钮，前台、后台、冷启动都算）走 `onOpen`。
- **统一弹窗**：通知图标、渠道只配一处，宿主不用再引 `flutter_local_notifications`。
- **不绑定后端**：令牌注册到哪、推送怎么发，由你的服务端决定。

| 手机 | 走哪个通道 | `PushToken.channel` |
|---|---|---|
| iPhone | APNs | `APNS` |
| 华为 | 华为推送（HMS） | `HUAWEI` |
| 荣耀（MagicOS 4.0+） | 荣耀推送；老荣耀机型退回 HMS | `HONOR` / `HUAWEI` |
| 小米 / 红米 / POCO | 小米推送 | `XIAOMI` |
| OPPO / 一加 / 真我 | OPPO 推送 | `OPPO` |
| vivo / iQOO | vivo 推送 | `VIVO` |
| 三星、Pixel 及其它 | FCM | `FCM` |

某家没配置，或者这台手机不支持，就自动退回 FCM。FCM 也没配置时拿不到令牌，但本地通知照常可用。

---

## 目录

1. [安装](#1-安装)
2. [配置](#2-配置)
3. [调用](#3-调用)
4. [API](#4-api)
5. [通知由谁弹出](#5-通知由谁弹出)
6. [服务端怎么发推送](#6-服务端怎么发推送)
7. [⚠️ 各厂商注意事项（上线前必读）](#7-️-各厂商注意事项上线前必读)
8. [示例工程](#8-示例工程)
9. [常见问题](#9-常见问题)

---

## 1. 安装

```yaml
dependencies:
  flutter_push_plus:
    git:
      url: https://github.com/20156284/flutter_push_plus.git
      ref: v0.4.3
```

最低要求：Flutter 3.38.1、iOS 15.0、安卓 minSdk 24、compileSdk 36。

## 2. 配置

### 2.1 Android：`android/gradle.properties`

只填你要用的厂商，**不填的整个不会编进包**：

```properties
# 通知渠道，不填时是 push / Push：OPPO、小米要求和服务端下发的 channel_id 一致（见第 7 节）；channelId 不要用纯数字，FCM 读不到
pushPlus.channelId=im
pushPlus.channelName=消息
# 通知栏小图标（android/app/src/main/res/drawable/ 下的资源名，白色透明底，必须存在）；本地、前台、FCM 后台通知共用
pushPlus.icon=ic_notify
# 来电等全屏通知要用 showNotification(fullScreen: true) 时才开（Google Play 对该权限有审核要求）
#pushPlus.fullScreenIntent=true

# FCM（三星、Pixel、海外机）。也可以不填，改放 google-services.json 并接入 google-services 插件
pushPlus.fcm.appId=1:1234567890:android:abcdef
pushPlus.fcm.apiKey=AIza...
pushPlus.fcm.projectId=my-project
pushPlus.fcm.senderId=1234567890

# 华为（AppGallery Connect → 项目设置 → 常规 → APP ID）
pushPlus.huawei.appId=104xxxxxx

# 荣耀（荣耀开发者服务平台 → 应用信息 → APP ID，照控制台的纯数字原样填）
pushPlus.honor.appId=104xxxxxx

# 小米（还要把 MiPush_SDK_Client_x.x.x.aar 放进 android/app/libs/）
pushPlus.xiaomi.appId=2882303761xxxxxxxxx
pushPlus.xiaomi.appKey=5xxxxxxxxxxxx

# OPPO（还要把 com.heytap.msp_Vx.x.x.aar 放进 android/app/libs/）
pushPlus.oppo.appKey=xxxxxxxx
pushPlus.oppo.appSecret=xxxxxxxx

# vivo（APP ID 照控制台的纯数字原样填）
pushPlus.vivo.appId=10xxxx
pushPlus.vivo.apiKey=xxxxxxxx
```

成对的键（如 `vivo.appId` + `vivo.apiKey`）要一起填，缺一个构建会直接报错；填了小米、OPPO 却没放 aar 也会报错。

全屏通知要在锁屏上亮屏显示，还要给 `AndroidManifest.xml` 的主 Activity 加 `android:showWhenLocked="true"` 和 `android:turnScreenOn="true"`。

各家 SDK 怎么来：

| 厂商 | SDK | 你要做什么 |
|---|---|---|
| FCM | `firebase-messaging` 24.1.0 | 无 |
| 华为 | `com.huawei.hms:push` 6.13.0.301 | 无（插件自动加华为 Maven 仓库） |
| 荣耀 | `com.hihonor.mcs:push` 10.0.39.302 | 无（插件自动加荣耀 Maven 仓库） |
| vivo | `vivo:vpush` 4.1.7.0 | 无（插件自动加 vivo Maven 仓库） |
| 小米 | 官方只提供 aar | 从 [小米开放平台](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1544) 下载，放进 `android/app/libs/` |
| OPPO | 官方只提供 aar | 从 [OPPO 开放平台](https://open.oppomobile.com/new/developmentDoc/info?id=11219) 下载，放进 `android/app/libs/` |

小米和 OPPO 官方没有说明 SDK 能不能随插件再分发，所以插件不带它们的 aar。你把 aar 放进 `app/libs/` 后，插件会自动识别并引用，不用改 gradle。OPPO 的旧版 aar（如 3.5.x）还依赖 `commons-codec`，要么用新版，要么自己给 `:app` 加上。

用 `flutter build apk -v` 构建，日志里能看到实际启用了哪些通道：
```
flutter_push_plus: channels = APNS(iOS) + [fcm, huawei, vivo]
```

插件内部用 `flutter_local_notifications` 弹通知（宿主不用引它，按钮回调的 receiver 也由插件自动声明），但它要求宿主的 `android/app/build.gradle.kts` 开启 desugaring：

```kotlin
android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
```

### 2.2 iOS

1. Xcode → Signing & Capabilities → `+ Capability` → **Push Notifications**；要用 `timeSensitive` 再加 **Time Sensitive Notifications**。
2. 建议在 `AppDelegate` 的 `didFinishLaunchingWithOptions` 里加一行（苹果要求启动完成前设好，否则「App 被杀后点通知拉起」那一次可能收不到）：

```swift
UNUserNotificationCenter.current().delegate = self
```

不加也能用：插件会在注册时自动补上，热启动的点击、前台推送都正常，只有新模板（UIScene）下冷启动那一次有丢的可能。

只要声明了 `foreground: false` 的按钮，就**必须**在 `AppDelegate` 的 `didFinishLaunchingWithOptions` 里加上下面这段，让后台 isolate 能用插件，否则点按钮时 App 会崩（App 活着时也一样）。⚠️ App 被杀后点按钮的场景 iOS 上还没实测，安卓已实测通过：

```swift
import flutter_local_notifications

FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { GeneratedPluginRegistrant.register(with: $0) }
```

## 3. 调用

```dart
// App 被杀时点了「拒绝」这类按钮：后台执行，不拉起界面。必须是顶层函数
@pragma('vm:entry-point')
Future<void> onBackgroundAction(PushMessage m) async => api.rejectCall(m.data['callId']);

// ⚠️ 在用户同意隐私政策之后再调（小米、vivo、华为等应用商店的合规要求）
await FlutterPushPlus.init(
  // 拿到或更新了令牌：连同通道名一起注册到你的服务端
  onToken: (t) => api.registerDevice(channel: t.channel, token: t.token, environment: t.environment?.name),
  // App 活着时收到远程推送（默认同时弹横幅，showInForeground: false 可关；各通道差异见第 5 节）
  onMessage: (m) => debugPrint('收到 ${m.title}: ${m.data}'),
  // 用户点了通知或按钮：远程、本地统一走这里
  onOpen: (m) => switch (m.actionId) {
    'accept' => callPage.accept(m.data['callId']),
    'reject' => api.rejectCall(m.data['callId']),
    _ => router.push(m.data['page'] as String? ?? '/'),
  },
  onBackgroundAction: onBackgroundAction,
  // 可选：按钮组（iOS 要求启动时注册）、额外的安卓渠道
  categories: const [
    PushCategory('call', [
      PushAction('reject', '拒绝', destructive: true),
      PushAction('accept', '接听', foreground: true),
    ]),
  ],
  notificationChannels: const [PushNotificationChannel('call', '来电', importance: PushImportance.max, sound: false)],
);

await FlutterPushPlus.requestPermission(); // 弹系统授权框（Web 要在点击事件里调）

// 本地通知：点了同样进 onOpen，data 原样带回（保留 int/bool 等类型）
await FlutterPushPlus.showNotification(
  id: 1001,
  title: '张三',
  body: '晚上一起吃饭吗？',
  data: {'page': '/chat', 'conversationId': 'c42', 'unread': 3},
);

// 来电：带按钮、全屏、常驻
await FlutterPushPlus.showNotification(
  id: 2001, title: '李四', body: '邀请你语音通话',
  data: {'callId': 'call-7'}, category: 'call', channelId: 'call',
  ongoing: true, fullScreen: true,
);
```

> 冷启动（App 被杀后点通知拉起）时，`onOpen` 会在 `init` 里回调。这时首页可能还没建好，建议先把消息存起来，等首页出来再跳。

## 4. API

所有方法都在 `FlutterPushPlus` 上，命名统一为「动词 + 对象」：

| 方法 | 说明 |
|---|---|
| `init({onToken, onMessage, onOpen, onBackgroundAction, showInForeground, notificationChannels, categories})` | 启动推送，App 生命周期内调一次 |
| `getToken()` | `PushToken(channel, token, environment)`；还没拿到时为 `null`，拿到后走 `onToken` |
| `getPermission()` | `PushPermission.granted / denied / notDetermined`；`notDetermined` 只有 Web 有，移动端未授权一律是 `denied` |
| `requestPermission()` | 申请通知权限，返回是否授权；安卓上已有权限框未关时再调会抛 `PlatformException` |
| `openNotificationSettings()` | 打开本 App 的系统通知设置页（用户拒绝过、或 ColorOS/vivo 默认关通知时引导） |
| `showNotification({id, title, body, data, channelId, category, silent, ongoing, fullScreen, timeSensitive, badge})` | 弹通知。`silent` 这条通知不响不振（如改写已显示的通知）；`ongoing`/`fullScreen` 仅安卓（`fullScreen` 自动按来电归类，勿扰时能否放行看用户的勿扰设置）；`timeSensitive`/`badge` 仅 iOS |
| `cancelNotification(id)` / `cancelAllNotifications()` | 撤掉通知 |
| `createNotificationChannel(PushNotificationChannel)` / `deleteNotificationChannel(id)` | 运行时增删渠道（重要性、声音、振动建好后不可改，要变就换 id）。iOS 没有渠道，但 `sound` 也决定通知是否出声；`channelId` 传未创建的渠道，debug 下两端都会断言 |

数据模型：

| 类型 | 字段 |
|---|---|
| `PushMessage` | `source`（remote / local）、`title`、`body`（安卓远程推送被点击时系统不回传，为 `null`，只有 `data` 一定在）、`data`、`actionId`（点按钮时有值；远程推送的按钮仅 iOS 有） |
| `PushToken` | `channel`（APNS / FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO）、`token`、`environment`（仅 iOS：`sandbox` / `production`，安卓与无法判定时为 `null`，见下节） |
| `PushEnvironment` | `sandbox` / `production` |
| `PushNotificationChannel` | `id`、`name`、`importance`（`PushImportance.low / normal / high / max`，默认 `high`，`high` 及以上才弹横幅）、`sound`、`vibrate` |
| `PushCategory` | 按钮组：`id`、`actions` |
| `PushAction` | 按钮：`id`、`title`、`foreground`（点了是否拉起 App，默认 `false`）、`destructive`（仅 iOS，红色） |
| `PushBackgroundHandler` | `onBackgroundAction` 的类型，必须是顶层或静态函数 |

`pushPlusBackgroundEntry` 是插件内部入口，不要调用。

### APNs 令牌环境

令牌属于沙箱还是正式环境，由描述文件的 `aps-environment` 决定，与 Debug、Release 编译模式无关。插件在 iOS 上这样判定，`PushToken.environment` 直接给出：

| 安装方式 | environment |
|---|---|
| 模拟器 | `sandbox` |
| Xcode 直装（开发描述文件） | `sandbox` |
| Ad Hoc / Enterprise（分发描述文件，`aps-environment=production`） | `production` |
| TestFlight、App Store（无内嵌描述文件） | `production` |
| 描述文件解析失败或缺 `aps-environment`、iOS 包跑在 Mac 上、安卓 | `null` |

上报服务端时按它选 APNs 网关；为 `null` 时自行兜底。

## 5. 通知由谁弹出

| App 状态 | 远程推送 | 本地通知 |
|---|---|---|
| 后台 / 被杀 | **系统通知栏**（APNs、各厂商、FCM 自己弹） | — |
| 前台 | 见下表 | 插件弹（`showNotification`） |

为什么后台一定交给系统：App 被杀后 Dart 根本没在运行，只有系统能弹；国产 ROM 上「静默消息 + 自己弹」会被限制、延迟甚至丢失，所以厂商通知栏消息是唯一可靠的方式。

App 活着时，不同通道、不同消息类型的行为：

| 通道 / 消息 | 谁弹 | 回调 `onMessage` | `showInForeground` |
|---|---|---|---|
| iOS 通知（前台） | 系统横幅 | 是 | 生效 |
| iOS 通知（后台）、静默推送 | 系统 / 不弹 | 否 | — |
| FCM 通知消息（前台） | 插件代弹 | 是 | 生效 |
| FCM 通知消息（后台） | 系统 | 否 | — |
| FCM 数据消息（前后台，引擎活着，即已调 `init`） | 不弹 | 是 | 不生效 |
| 华为、荣耀、小米、OPPO、vivo 通知栏消息 | 系统（前台也是） | 否 | 不生效 |
| 华为、荣耀透传（引擎活着） | 不弹 | 是 | 不生效 |
| 小米透传（引擎活着，含后台） | 带标题或正文时插件代弹 | 是 | 生效 |

## 6. 服务端怎么发推送

**一条消息，一套字段，所有通道都一样**。服务端只需要准备好这三样，再按设备注册时上报的 `channel` 填进对应厂商的接口：

```json
{ "title": "张三", "body": "晚上一起吃饭吗？", "data": { "page": "/chat", "conversationId": "c42" } }
```

App 收到后，不管是哪个通道、App 在前台后台还是被杀，点击时 `onOpen` 拿到的都是同一个 `data`：`{page: /chat, conversationId: c42}`。

为了两端一致，请遵守：

- **值只用字符串**：安卓点击时非字符串的值会被丢掉，iOS 则保留原类型。
- **不要用保留键**：`from`、`collapse_key`、`route`、`cached_engine_id`、`cached_engine_group_id`、`dart_entrypoint`、`background_mode`、`dart-flags`、`trace-allowlist`、`trace-skia-allowlist`、`trace-to-file`，小米的 `notify_effect`、`channel_id`，以及 `google.`、`gcm.`、`android.`、`androidx.`、`_push_`、`vivo_push_` 开头的键，安卓点击时会被过滤。
- **`data` 不可信**：其他 App 也能带字符串 extras 拉起你的启动页，跳转前要校验（如路由白名单）。

各通道只是「把 `data` 放在哪」和「点击动作写什么」不同：

| `channel` | 发送接口 | 点击动作 | `data` 放在哪 | IM 消息分类 |
|---|---|---|---|---|
| `APNS` | APNs HTTP/2（按设备上报的环境选沙箱或正式网关） | 默认 | 和 `aps` 平级的自定义键 | — |
| `FCM` | `fcm.googleapis.com/v1/.../messages:send` | 默认 | `message.data`（值必须是字符串） | — |
| `HUAWEI` | `push-api.cloud.huawei.com/v1/{appId}/messages:send` | `click_action.type=3` | `message.data`（JSON 字符串） | `category: "IM"` |
| `HONOR` | `push-api.cloud.honor.com/api/v1/{appId}/sendMessage` | `clickAction.type=3` | `android.data`（JSON 字符串） | `importance: "NORMAL"` |
| `XIAOMI` | `api.xmpush.xiaomi.com/v3/message/regid` | `extra.notify_effect=1` | 每个键写成 `extra.<键>` | `extra.channel_id=<私信渠道>` |
| `OPPO` | `api-push-cn.heytapmobi.com/server/v1/message/notification/unicast` | `click_action_type=0` | `action_parameters`（JSON 字符串） | `category: "IM"` + `channel_id` |
| `VIVO` | `api-push.vivo.com.cn/message/send` | `skipType=1` | `clientCustomMap` | `category: "IM"` |

> 服务端建议也封装成一个函数：`send(device, title, body, data)`，内部按 `device.channel` 分发。业务代码只关心标题、正文和 `data`。

<details>
<summary>展开：同一条消息在各通道的完整请求体</summary>

```jsonc
// APNS
{"aps":{"alert":{"title":"张三","body":"晚上一起吃饭吗？"},"sound":"default"},"page":"/chat","conversationId":"c42"}

// FCM
{"message":{"token":"<令牌>","notification":{"title":"张三","body":"晚上一起吃饭吗？"},
 "android":{"notification":{"channel_id":"im"}},"data":{"page":"/chat","conversationId":"c42"}}}

// HUAWEI
{"message":{"token":["<令牌>"],"data":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}",
 "android":{"notification":{"title":"张三","body":"晚上一起吃饭吗？","importance":"NORMAL","category":"IM","click_action":{"type":3}}}}}

// HONOR
{"token":["<令牌>"],"android":{"data":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}",
 "notification":{"title":"张三","body":"晚上一起吃饭吗？","importance":"NORMAL","clickAction":{"type":3}}}}

// XIAOMI（表单格式）
registration_id=<令牌>&restricted_package_name=<包名>&title=张三&description=晚上一起吃饭吗？&notify_type=-1
&extra.notify_effect=1&extra.channel_id=<私信渠道ID>&extra.page=/chat&extra.conversationId=c42

// OPPO（官方 V1.9.3 文档为表单格式：message=<下面的 JSON>，以最新文档为准）
{"target_type":2,"target_value":"<令牌>","notification":{"title":"张三","content":"晚上一起吃饭吗？","click_action_type":0,
 "action_parameters":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}","channel_id":"im","category":"IM","notify_level":2}}

// VIVO
{"regId":"<令牌>","notifyType":4,"title":"张三","content":"晚上一起吃饭吗？","skipType":1,
 "category":"IM","clientCustomMap":{"page":"/chat","conversationId":"c42"},"requestId":"<uuid>"}
```

</details>

**本地调试**：不经服务器也能模拟，两端拿到的 `data` 和真推送一样：

```bash
# iOS 模拟器：模拟一条远程推送
xcrun simctl push booted <bundle id> payload.json
# Android：模拟「点通知拉起 App」
adb shell am start -n <包名>/.MainActivity --es page /chat --es conversationId c42
```

## 7. ⚠️ 各厂商注意事项（上线前必读）

### 通用

- **隐私合规**：`init` 一定要在用户同意隐私政策**之后**再调；隐私政策里要列出用到的推送 SDK。否则各家应用商店可能拒审。
- **消息分类**：国内各家都区分「通讯/服务类」和「营销类」。不做分类的消息按营销类处理：**每天限几条，而且只在下拉通知栏里才显示**。IM 消息一定要按下面各家的规则申请和标记。
- **通知权限**：Android 13+ 要运行时授权；ColorOS、vivo 新装的 App 默认关通知。拒绝过授权的用户要用 `openNotificationSettings()` 引导去设置里打开。
- **启动页 extras**：插件把「不带 URI 的启动 Intent 里的字符串 extras」当成推送字段，用过的键会被清掉。如果你自己用字符串 extras 拉起首页，也会触发 `onOpen`。

### 华为
- 先在 AppGallery Connect 里**开通推送服务**，再去取令牌。
- 令牌可能延迟到 `onToken` 才回来，这是正常现象；不要校验令牌长度，长度会变。
- IM 消息用 `importance: NORMAL` 加上 `category: IM`，要先在后台申请「自分类权益」。
- 透传消息在 App 进程不在时收不到，点击跳转请用通知消息。

### 荣耀
- 只支持 MagicOS 4.0 及以上（海外 4.2+）。更老的荣耀机型会自动退回华为 HMS。
- 管理后台登记的 **签名 SHA256 必须和实际打包的签名一致**，否则注册失败。
- 营销类消息（`importance: LOW`）只在下拉通知栏里显示；同一个 App 超过 49 条会被丢弃。

### 小米
- ⚠️ 小米 SDK 需要登录开放平台才能下载，本插件的小米通道用第三方重新打包的 6.0.1 aar 编译通过，**还没有用官方 aar 和真机验证**。如果遇到问题，欢迎提 issue。
- **正式环境要求 App 已在小米应用商店上架**，而且后台登记的包名要和 applicationId 一致。
- IM 消息要走「私信」：先在小米后台**申请 channel_id**（最多 8 个），服务端带 `extra.channel_id`。不申请的话，每台设备每天大约只有 1 条。
- 海外版 SDK 需要在注册前设置区域，当前插件只适配国内版。

### OPPO（含一加、真我）
- IM 走「通讯与服务」通道：要**发邮件申请，而且 App 要先在 OPPO 软件商店上架**。不申请的话每台设备每天只有 2 条，而且只在下拉通知栏里显示。
- 服务端的 `channel_id` **必须**等于 `pushPlus.channelId`（或你用 `notificationChannels` 建的渠道 id），而且要在推送平台登记一致的渠道 ID 和名称。**定下来之后不能改、不能删**，否则 Android 8+ 不显示通知。
- 令牌在刷机、卸载或长期不联网后会失效，App 每次启动都会重新上报。

### vivo（含 iQOO）
- `category` 必填，而且要大写；IM 填 `IM`，只能用于**真人之间**的私聊和群聊（官方号、群发都算违规）。其余系统类目要先申请消息模板。
- 不支持透传消息，也不支持自定义通知渠道。
- 调试时可以带上 `pushMode: 1`，每天 1000 条，不受频控。

### FCM
- 国行手机一般没有谷歌服务，FCM 拿不到令牌。所以国产品牌请配好各自的厂商通道。
- App 在前台时收到的通知消息，由插件代为弹出横幅（受 `showInForeground` 控制，下发的 `channel_id` 本次启动已在 Dart 建过时用它，否则用默认渠道）；在后台时由系统展示，系统里存在下发的渠道就用它，否则用 `pushPlus.channelId`。

## 8. 示例工程

`example/` 可以直接运行：申请权限、查看令牌、弹本地通知、带「拒绝/接听」按钮的来电通知、点通知跳到详情页（显示来源、标题正文、按钮 id 和 data 的类型）、打开系统通知设置。iOS 真机要看令牌，先给 Runner 加 Push Notifications 能力。

```bash
cd example && flutter run
```

## 9. 常见问题

**iOS 点了通知没反应？** 插件只在宿主没设置通知中心代理时才自动设置。如果你或别的插件把代理设成了其它对象，要让那个对象把回调转给 `FlutterAppDelegate`。

**怎么确认走的是哪个通道？** 看 logcat 里的 `flutter_push_plus: channel XXX`，或者看 `onToken` 回调里的 `channel`。

**国产手机走了 FCM？** 说明这家没配置，或者这台手机的系统不支持该厂商推送（logcat 里会有 `XXX not supported on this device` 或 `XXX unavailable`）。注册失败时 logcat 也有带错误码的日志。

**gradle 报找不到 `com.huawei.hms:push` 之类的依赖？** 你的 `settings.gradle` 里设置了 `RepositoriesMode.PREFER_SETTINGS`，插件加的仓库不生效。这时把下面几个仓库手动加到 `dependencyResolutionManagement` 里：`https://developer.honor.com/repo`、`https://repos.vivo.com.cn/maven/repository/external-lib/`、`https://developer.huawei.com/repo/`（华为的放在最后）。`FAIL_ON_PROJECT_REPOS` 与插件不兼容，构建会直接失败，要改掉。

**项目里原来直接用了 `flutter_local_notifications`？** 改成用插件的 `showNotification` / `notificationChannels` / `categories`，然后删掉自己的初始化。它只能有一个初始化者，两边都初始化会抢点击回调。

**Web 上能用吗？** 能弹本地通知、能申请权限（必须在点击事件里调用）；没有远程推送，`getToken()` 恒为 `null`。浏览器不支持通知（如 iOS Safari 普通标签）或未授权时，`showNotification` 直接跳过不报错；`getPermission()` 在不支持或已拒绝时返回 `denied`，还没询问过时返回 `notDetermined`。如果构建时报找不到 `flutter_web_plugins`，在 pubspec 加上 `flutter_web_plugins: {sdk: flutter}`。

## License

MIT
