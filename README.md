# flutter_push_plus

一套接口管住 **远程推送 + 本地通知 + 点击跳转**，安卓按手机品牌自动走厂商通道。

- **使用者只做两件事**：在 `android/gradle.properties` 填各家 ID，在 Dart 里调一次 `init`。
- **按需打包**：哪家没填 ID，哪家的 SDK 就不编进 APK，不会因为接了插件而臃肿。
- **统一回调**：令牌统一走 `onToken`，前台收到的推送统一走 `onMessage`，用户点击（远程推送、本地通知，前台、后台、冷启动都算）统一走 `onOpen`。
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
5. [服务端怎么发（各厂商）](#5-服务端怎么发各厂商)
6. [⚠️ 各厂商注意事项（上线前必读）](#6-️-各厂商注意事项上线前必读)
7. [示例工程](#7-示例工程)
8. [常见问题](#8-常见问题)

---

## 1. 安装

```yaml
dependencies:
  flutter_push_plus:
    git:
      url: https://github.com/20156284/flutter_push_plus.git
      ref: v0.2.1
```

## 2. 配置

### 2.1 Android：`android/gradle.properties`

只填你要用的厂商，**不填的整个不会编进包**：

```properties
# 通知渠道：OPPO、小米要求和服务端下发的 channel_id 一致（见第 6 节）
pushPlus.channelId=im
pushPlus.channelName=消息
# 通知栏小图标（android/app/src/main/res/drawable/ 下的资源名，白色透明底）
pushPlus.icon=ic_notify

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

另外，本地通知依赖 `flutter_local_notifications`，宿主的 `android/app/build.gradle.kts` 需要开启 desugaring：

```kotlin
android { compileOptions { isCoreLibraryDesugaringEnabled = true } }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
```

### 2.2 iOS

1. Xcode → Signing & Capabilities → `+ Capability` → **Push Notifications**。
2. `AppDelegate.swift` 设置通知中心代理（不设就收不到点击回调和前台推送）：

```swift
UNUserNotificationCenter.current().delegate = self
```

## 3. 调用

```dart
// ⚠️ 在用户同意隐私政策之后再调（小米、vivo、华为等应用商店的合规要求）
await FlutterPushPlus.init(
  // 用户点了通知：远程推送、本地通知都走这里，参数是服务端下发的自定义字段
  onOpen: (data) => router.push(data['page'] as String? ?? '/', extra: data),
  // 拿到或更新了令牌：连同通道名一起注册到你的服务端
  onToken: (t) => api.registerDevice(channel: t.channel, token: t.token),
  // App 在前台时收到的远程推送（默认同时弹系统横幅，showForeground: false 可关）
  onMessage: (data) => debugPrint('收到推送 $data'),
);

await FlutterPushPlus.requestPermission(); // 弹系统授权框

await FlutterPushPlus.showLocal(           // 本地通知，点了也会进 onOpen
  id: 1001,
  title: '张三',
  body: '晚上一起吃饭吗？',
  payload: {'page': '/chat', 'conversationId': 'c42'},
);
```

> 冷启动（App 被杀后点通知拉起）时，`onOpen` 会在 `init` 里回调。这时首页可能还没建好，建议先把数据存起来，等首页出来再跳。

## 4. API

| 方法 | 说明 |
|---|---|
| `init({onOpen, onToken, onMessage, showForeground, local, localIcon})` | 启动推送。`local: false` 表示你自己管 `flutter_local_notifications`，插件不接管本地通知 |
| `getToken()` | `PushToken(channel, token)`；还没拿到时为 `null`，拿到后走 `onToken` |
| `requestPermission()` | 申请通知权限（iOS 和 Android 13+ 会弹系统框），返回是否已授权 |
| `openNotificationSettings()` | 打开本 App 的系统通知设置页。用户拒绝过授权，或系统默认关了通知（ColorOS、vivo），就引导到这里 |
| `showLocal({id, title, body, payload, channelId, channelName, icon, badge})` | 弹本地通知，默认用 `pushPlus.channelId` 渠道 |
| `cancelLocal(id)` | 撤掉一条本地通知 |

## 5. 服务端怎么发（各厂商）

各家统一约定：**点击动作选「打开应用」，自定义字段放在各家的「自定义参数」里**。插件从启动 Intent 里取出这些字段，交给 `onOpen`。

下面都以「打开 App，带上 `{page:'/chat', conversationId:'c42'}`」为例：

**APNs**：自定义字段和 `aps` 平级
```json
{"aps":{"alert":{"title":"张三","body":"晚上一起吃饭吗？"},"sound":"default"},
 "page":"/chat","conversationId":"c42"}
```

**FCM**（HTTP v1）：字段放 `data`，值必须是字符串
```json
{"message":{"token":"<令牌>","notification":{"title":"张三","body":"晚上一起吃饭吗？"},
 "android":{"notification":{"channel_id":"im"}},
 "data":{"page":"/chat","conversationId":"c42"}}}
```

**华为**：`POST https://push-api.cloud.huawei.com/v1/{appId}/messages:send`
```json
{"message":{"token":["<令牌>"],"data":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}",
 "android":{"notification":{"title":"张三","body":"晚上一起吃饭吗？",
   "importance":"NORMAL","category":"IM","click_action":{"type":3}}}}}
```

**荣耀**：`POST https://push-api.cloud.honor.com/api/v1/{appId}/sendMessage`
```json
{"token":["<令牌>"],"android":{"data":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}",
 "notification":{"title":"张三","body":"晚上一起吃饭吗？","importance":"NORMAL","clickAction":{"type":3}}}}
```

**小米**：`POST https://api.xmpush.xiaomi.com/v3/message/regid`（表单格式）
```
registration_id=<令牌>&restricted_package_name=<包名>&title=张三&description=晚上一起吃饭吗？
&notify_type=-1&extra.notify_effect=1&extra.channel_id=<私信渠道ID>
&extra.page=/chat&extra.conversationId=c42
```

**OPPO**：`POST https://api-push-cn.heytapmobi.com/server/v1/message/notification/unicast`
```json
{"target_type":2,"target_value":"<令牌>","notification":{"title":"张三","content":"晚上一起吃饭吗？",
 "click_action_type":0,"action_parameters":"{\"page\":\"/chat\",\"conversationId\":\"c42\"}",
 "channel_id":"im","category":"IM","notify_level":2}}
```

**vivo**：`POST https://api-push.vivo.com.cn/message/send`
```json
{"regId":"<令牌>","notifyType":4,"title":"张三","content":"晚上一起吃饭吗？","skipType":1,
 "category":"IM","clientCustomMap":{"page":"/chat","conversationId":"c42"},"requestId":"<uuid>"}
```

**本地调试**：iOS 模拟器不经服务器也能模拟一条推送：`xcrun simctl push booted <bundle id> payload.json`。
安卓可以模拟「点通知拉起 App」：`adb shell am start -n <包名>/.MainActivity --es page /chat --es conversationId c42`。

## 6. ⚠️ 各厂商注意事项（上线前必读）

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
- 服务端的 `channel_id` **必须**等于 `pushPlus.channelId`，而且要在推送平台登记一致的渠道 ID 和名称。**定下来之后不能改、不能删**，否则 Android 8+ 不显示通知。
- 令牌在刷机、卸载或长期不联网后会失效，App 每次启动都会重新上报。

### vivo（含 iQOO）
- `category` 必填，而且要大写；IM 填 `IM`，只能用于**真人之间**的私聊和群聊（官方号、群发都算违规）。其余系统类目要先申请消息模板。
- 不支持透传消息，也不支持自定义通知渠道。
- 调试时可以带上 `pushMode: 1`，每天 1000 条，不受频控。

### FCM
- 国行手机一般没有谷歌服务，FCM 拿不到令牌。所以国产品牌请配好各自的厂商通道。
- App 在前台时收到的通知消息，由插件代为弹出横幅（受 `showForeground` 控制）；在后台时由系统展示，渠道用 `pushPlus.channelId`。

## 7. 示例工程

`example/` 可以直接运行：申请权限、查看令牌、弹本地通知、点通知跳到详情页（显示收到的字段）、打开系统通知设置。

```bash
cd example && flutter run
```

## 8. 常见问题

**iOS 点了通知没反应？** 检查 `AppDelegate` 里有没有设置 `UNUserNotificationCenter.current().delegate = self`。

**怎么确认走的是哪个通道？** 看 logcat 里的 `flutter_push_plus: channel XXX`，或者看 `onToken` 回调里的 `channel`。

**国产手机走了 FCM？** 说明这家没配置、`app/libs` 里缺 aar，或者这台手机的系统不支持该厂商推送（logcat 里会有 `XXX unavailable`）。

**gradle 报找不到 `com.huawei.hms:push` 之类的依赖？** 你的 `settings.gradle` 里设置了 `RepositoriesMode.FAIL_ON_PROJECT_REPOS`，插件就没法自动加仓库。这时把下面几个仓库手动加到 `dependencyResolutionManagement` 里：`https://developer.honor.com/repo`、`https://repos.vivo.com.cn/maven/repository/external-lib/`、`https://developer.huawei.com/repo/`（华为的放在最后）。

**和项目里已有的 `flutter_local_notifications` 冲突？** 用 `init(local: false)`，插件就只管远程推送。

## License

MIT
