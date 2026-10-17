# flutter_push_plus

一套接口管住 **远程推送 + 本地通知 + 点击跳转**，安卓按手机品牌自动走厂商通道。

- **使用者只做两件事**：在 `android/gradle.properties` 填各家 ID，在 Dart 里调一次 `init`。
- **按需打包**：哪家没填 ID，哪家的 SDK 就不编进 APK，不会因为接了插件而臃肿。
- **统一模型**：远程推送、本地通知、到达、点击、按钮，全部是同一个 `PushMessage`（标题 / 正文 / data / 来源 / 按钮 id）。
- **统一回调**：令牌走 `onToken`，前台收到的推送走 `onMessage`，用户点击（远程推送、本地通知、通知按钮，前台、后台、冷启动都算）走 `onOpen`。
- **统一弹窗**：通知图标、渠道只配一处；本地通知和前台推送走同一条展示路径，宿主不用再引 `flutter_local_notifications`。
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
      ref: v0.3.0
```

## 2. 配置

### 2.1 Android：`android/gradle.properties`

只填你要用的厂商，**不填的整个不会编进包**：

```properties
# 通知渠道：OPPO、小米要求和服务端下发的 channel_id 一致（见第 6 节）
pushPlus.channelId=im
pushPlus.channelName=消息
# 通知栏小图标（android/app/src/main/res/drawable/ 下的资源名，白色透明底）；本地、前台、FCM 后台通知共用
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

各家 SDK 怎么来：

| 厂商 | SDK | 你要做什么 |
|---|---|---|
| FCM | `firebase-messaging` 24.1.0 | 无 |
| 华为 | `com.huawei.hms:push` 6.13.0.301 | 无（插件自动加华为 Maven 仓库） |
| 荣耀 | `com.hihonor.mcs:push` 10.0.39.302 | 无（插件自动加荣耀 Maven 仓库） |
| vivo | `vivo:vpush` 4.1.7.0 | 无（插件自动加 vivo Maven 仓库） |
| 小米 | 官方只提供 aar | 从 [小米开放平台](https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1544) 下载，放进 `android/app/libs/` |
| OPPO | 官方只提供 aar | 从 [OPPO 开放平台](https://open.oppomobile.com/new/developmentDoc/info?id=11219) 下载，放进 `android/app/libs/` |

小米和 OPPO 官方没有说明 SDK 能不能随插件再分发，所以插件不带它们的 aar。你把 aar 放进 `app/libs/` 后，插件会自动识别并引用，不用改 gradle。

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

Xcode → Signing & Capabilities → `+ Capability` → **Push Notifications**。不用改 `AppDelegate`，插件会自动接好通知中心代理。

只有用 `onBackgroundAction`（App 被杀时点了不拉起 App 的按钮）才需要在 `AppDelegate` 里加一行，让后台 isolate 能用插件（⚠️ iOS 上这个场景还没实测，安卓已实测通过）：

```swift
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
  onToken: (t) => api.registerDevice(channel: t.channel, token: t.token),
  // App 在前台时收到远程推送（默认同时弹横幅，showInForeground: false 可关）
  onMessage: (m) => debugPrint('收到 ${m.title}: ${m.data}'),
  // 用户点了通知或按钮：远程、本地统一走这里
  onOpen: (m) => m.actionId == 'accept'
      ? callPage.accept(m.data['callId'])
      : router.push(m.data['page'] as String? ?? '/'),
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
| `getToken()` | `PushToken(channel, token)`；还没拿到时为 `null`，拿到后走 `onToken` |
| `getPermission()` | `PushPermission.granted / denied / notDetermined` |
| `requestPermission()` | 申请通知权限，返回是否授权 |
| `openNotificationSettings()` | 打开本 App 的系统通知设置页（用户拒绝过、或 ColorOS/vivo 默认关通知时引导） |
| `showNotification({id, title, body, data, channelId, category, silent, ongoing, fullScreen, timeSensitive, badge})` | 弹通知。`silent` 改写已有通知时不再响；`ongoing`/`fullScreen` 仅安卓；`timeSensitive`/`badge` 仅 iOS |
| `cancelNotification(id)` / `cancelAllNotifications()` | 撤掉通知 |
| `createNotificationChannel(PushNotificationChannel)` / `deleteNotificationChannel(id)` | 运行时增删安卓渠道（渠道的声音/振动建好后不可改，要变就换 id） |

数据模型：

| 类型 | 字段 |
|---|---|
| `PushMessage` | `source`（remote / local）、`title`、`body`、`data`、`actionId`（点按钮时有值） |
| `PushToken` | `channel`（APNS / FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO）、`token` |
| `PushNotificationChannel` | `id`、`name`、`importance`、`sound`、`vibrate` |
| `PushCategory` / `PushAction` | 按钮组 / 按钮：`id`、`title`、`foreground`（点了是否拉起 App）、`destructive` |

## 5. 通知由谁弹出

| App 状态 | 远程推送 | 本地通知 |
|---|---|---|
| 后台 / 被杀 | **系统通知栏**（APNs、各厂商、FCM 自己弹） | — |
| 前台 | iOS：系统横幅；安卓 FCM：插件代弹。都受 `showInForeground` 控制，同时回调 `onMessage` | 插件弹（`showNotification`） |

为什么后台一定交给系统：App 被杀后 Dart 根本没在运行，只有系统能弹；国产 ROM 上「静默消息 + 自己弹」会被限制、延迟甚至丢失，所以厂商通知栏消息是唯一可靠的方式。
前台由插件统一弹出：图标、渠道和远程推送一致，点击也统一回到 `onOpen`。华为、荣耀、小米、OPPO、vivo 的通知在前台也由系统直接展示。

## 6. 服务端怎么发推送

**一条消息，一套字段，所有通道都一样**。服务端只需要准备好这三样，再按设备注册时上报的 `channel` 填进对应厂商的接口：

```json
{ "title": "张三", "body": "晚上一起吃饭吗？", "data": { "page": "/chat", "conversationId": "c42" } }
```

App 收到后，不管是哪个通道、App 在前台后台还是被杀，点击时 `onOpen` 拿到的都是同一个 `data`：`{page: /chat, conversationId: c42}`。

各通道只是「把 `data` 放在哪」和「点击动作写什么」不同：

| `channel` | 发送接口 | 点击动作 | `data` 放在哪 | IM 消息分类 |
|---|---|---|---|---|
| `APNS` | APNs HTTP/2 | 默认 | 和 `aps` 平级的自定义键 | — |
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

// OPPO
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
- **启动页 extras**：插件把「启动 Intent 里的字符串 extras」当成推送字段。如果你自己用字符串 extras 拉起首页，也会触发 `onOpen`。

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
- ⚠️ 小米 SDK 需要登录开放平台才能下载，本插件的小米通道**还没有经过编译和真机验证**。如果遇到问题，欢迎提 issue。
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
- App 在前台时收到的通知消息，由插件代为弹出横幅（受 `showInForeground` 控制）；在后台时由系统展示，渠道用 `pushPlus.channelId`。

## 8. 示例工程

`example/` 可以直接运行：申请权限、查看令牌、弹本地通知、带「拒绝/接听」按钮的来电通知、点通知跳到详情页（显示来源、按钮 id 和 data 的类型）、打开系统通知设置。

```bash
cd example && flutter run
```

## 9. 常见问题

**iOS 点了通知没反应？** 插件只在宿主没设置通知中心代理时才自动设置。如果你或别的插件把代理设成了其它对象，要让那个对象把回调转给 `FlutterAppDelegate`。

**怎么确认走的是哪个通道？** 看 logcat 里的 `flutter_push_plus: channel XXX`，或者看 `onToken` 回调里的 `channel`。

**国产手机走了 FCM？** 说明这家没配置、`app/libs` 里缺 aar，或者这台手机的系统不支持该厂商推送（logcat 里会有 `XXX unavailable`）。

**gradle 报找不到 `com.huawei.hms:push` 之类的依赖？** 你的 `settings.gradle` 里设置了 `RepositoriesMode.FAIL_ON_PROJECT_REPOS`，插件就没法自动加仓库。这时把下面几个仓库手动加到 `dependencyResolutionManagement` 里：`https://developer.honor.com/repo`、`https://repos.vivo.com.cn/maven/repository/external-lib/`、`https://developer.huawei.com/repo/`（华为的放在最后）。

**项目里原来直接用了 `flutter_local_notifications`？** 改成用插件的 `showNotification` / `notificationChannels` / `categories`，然后删掉自己的初始化。它只能有一个初始化者，两边都初始化会抢点击回调。

**Web 上能用吗？** 能弹本地通知、能申请权限（必须在点击事件里调用）；没有远程推送，`getToken()` 恒为 `null`。如果构建时报找不到 `flutter_web_plugins`，在 pubspec 加上 `flutter_web_plugins: {sdk: flutter}`。

## License

MIT
