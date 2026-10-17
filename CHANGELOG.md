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
