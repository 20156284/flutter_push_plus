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
