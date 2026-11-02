## 0.4.3

- `PushToken` 新增可空 `environment`（`PushEnvironment.sandbox / production`）：iOS 按描述文件的 `aps-environment` 判定，模拟器为 sandbox，App Store、TestFlight 为 production；安卓与无法判定时为 null。
- iOS 远程推送点按钮时 `onOpen` 带 `actionId`；`init` 之前的前台推送不再弹横幅。
- 宿主回调抛错不再打断 `init` 和代弹通知，错误走 `FlutterError.reportError`。
- 外来 payload 类型不符时不再抛错，原文放进 `data['payload']`；Web 上 `silent` 与渠道静音生效。
- 安卓：`pushPlus.channelName` 可直接写中文；`pushPlus.icon` release 不再被裁（资源不存在时构建报错）；填了小米、OPPO 配置却缺 aar、成对键缺一个都在构建期报错。
- 安卓：FCM 走 `google-services.json` 时不再在 `init` 之前生成令牌；注册失败都打日志且不影响本地通知；混淆规则按启用的厂商加载。
- 安卓：只清用掉的启动 extras；深链、Flutter 自身的 extras 不再误判成推送点击；进程被回收后重建不再重投旧点击。
- 安卓：华为、荣耀透传非 JSON 时原文放进 `data['payload']`；小米透传主体也放进 `data['payload']`（宿主 `data` 会多这个键）；小米点击的 `data` 不再带 `notify_effect`、`channel_id` 和保留键。
- 安卓：`PushImportance.low` 的通知优先级改为 low（之前落到 default）；FCM 前台代弹跟随下发的 `channel_id`（渠道已创建时）；OPPO 补接收权限；重复 `init` 会再回调一次令牌。
- 依赖下限提到 `flutter_local_notifications` 22.3.2。

## 0.4.2

- Web：浏览器没有 Notification API（iOS Safari 普通标签、部分 WebView）时不再抛错，权限视为 `denied`；未授权时 `showNotification` 直接跳过。

## 0.4.1

- iOS 通知是否出声跟随所用通知渠道的 `sound`（之前只看 `silent`，关了声音的渠道在 iOS 上仍会响）。

## 0.4.0（破坏性变更）

- 改名去歧义（`PushToken.channel` 指推送通道，通知渠道统一带 Notification）：`PushChannel`→`PushNotificationChannel`、`createChannel`→`createNotificationChannel`、`deleteChannel`→`deleteNotificationChannel`、`init(channels:)`→`init(notificationChannels:)`。
- 点击非本插件发的通知（如升级前留在通知栏的旧通知）不再抛错，原文放进 `data['payload']`。
- iOS 没有标题/正文时给 null，与安卓一致；补隐私清单（UserDefaults 声明）；APNs 注册失败打日志。
- 没有谷歌服务的手机不再选 FCM（之前会选中但永远拿不到令牌）。
- 通知图标没配或资源不存在时用 App 真实图标，宿主改过启动图标名也不会初始化失败。
- gradle.properties 里的值做 XML 转义；用错渠道/按钮组在 debug 下断言提示。
- pubspec 环境约束与 flutter_local_notifications 对齐（Flutter ≥ 3.38.1）。
- 修复：点过「不拉起 App 的按钮」后安卓令牌与前台推送再也收不到（后台引擎抢走了实例）。
- 修复：iOS 用后台按钮后完成回调被调两次（后台引擎重复注册应用代理）。
- 修复：从最近任务恢复时重复投递冷启动那次点击。
- 后台按钮：主引擎已销毁但进程还在时也能走 `onBackgroundAction`（等回执，1 秒超时）。
- 安卓 `fullScreen` 通知按来电归类（勿扰时放行），其余按消息；Web 同 id 替换时非静默会再次提醒。
- gradle.properties 成对的键缺一个时构建直接报错（如填了 vivo.appId 没填 vivo.apiKey）。

## 0.3.0（破坏性变更）

- 统一模型 `PushMessage`：远程/本地、到达/点击/按钮都是它；`onMessage`、`onOpen` 改收 `PushMessage`。
- 统一命名：`showLocal`→`showNotification`、`cancelLocal`→`cancelNotification`，新增 `cancelAllNotifications`、`getPermission`、`createChannel`、`deleteChannel`；`showForeground`→`showInForeground`。
- 插件独占 flutter_local_notifications：去掉 `local`、`localIcon` 参数，宿主不再直接用它；按钮回调 receiver 自动声明。
- 通知按钮：`categories` + `PushAction`，`onOpen` 带 `actionId`；App 被杀时走 `onBackgroundAction`。
- 渠道：`channels` / `createChannel`，`showNotification` 支持 `silent`、`ongoing`、`fullScreen`（`pushPlus.fullScreenIntent=true` 才加权限）、`timeSensitive`、`badge`。
- 图标只配 `pushPlus.icon` 一处：本地、前台、FCM 后台通知共用。
- 安卓前台远程推送改由 Dart 统一弹出；`data` 保留类型。
- iOS 自动设置通知中心代理，宿主不用改 AppDelegate。
- Web：本地通知与权限可用，远程推送为空操作。

## 0.2.1

- 修复：华为等厂商的令牌回调在子线程，直接调 Dart 会崩，统一切回主线程；相同令牌不重复回调。
- 修复：冷启动点小米通知拿不到字段（init 前就要按各厂商规则解析启动 Intent）。
- Android 7 打开通知设置退回应用详情页。

## 0.2.0

- Android 按品牌自动选通道：华为 HMS、荣耀、小米、OPPO、vivo，其余走 FCM；不配置的厂商不编进包。
- 配置统一写在宿主 `android/gradle.properties`（`pushPlus.*`），移除 Dart 侧 `FcmOptions`（破坏性变更）。
- 新增 `onMessage`（前台收到远程推送）、`showForeground`（前台弹系统横幅）、`openNotificationSettings()`。
- 统一通知渠道 `pushPlus.channelId`，FCM 后台通知与本地通知共用。
- 小米通道未经编译验证（SDK 需登录下载）。

## 0.1.0

- iOS APNs token and tap routing (cold start included).
- Android FCM token and tap routing; Firebase via `FcmOptions` or google-services.json.
- Local notifications (icon / title / body / badge / channel) with the same `onOpen` callback.
