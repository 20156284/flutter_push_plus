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
