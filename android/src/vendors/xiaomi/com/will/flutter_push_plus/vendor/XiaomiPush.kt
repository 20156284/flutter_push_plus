package com.will.flutter_push_plus.vendor

import android.content.Context
import android.content.Intent
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.pushConfig
import com.xiaomi.mipush.sdk.ErrorCode
import com.xiaomi.mipush.sdk.MiPushClient
import com.xiaomi.mipush.sdk.MiPushCommandMessage
import com.xiaomi.mipush.sdk.MiPushMessage
import com.xiaomi.mipush.sdk.PushMessageHelper
import com.xiaomi.mipush.sdk.PushMessageReceiver

/** 小米推送：小米 / 红米 / POCO。服务端用 notify_effect=1 打开应用，自定义字段放 extra.*。 */
class XiaomiPush : PushVendor {
  override val channel = "XIAOMI"

  override fun isSupported(context: Context) = true

  override fun register(context: Context, onToken: (String) -> Unit) {
    MiPushClient.getRegId(context)?.takeIf { it.isNotEmpty() }?.let(onToken)
    MiPushClient.registerPush(context, context.pushConfig("xiaomi.appId"), context.pushConfig("xiaomi.appKey"))
  }

  /** 预定义点击（notify_effect）不回调 Receiver，消息整包序列化在启动 Intent 里。 */
  @Suppress("DEPRECATION")
  override fun extractClick(intent: Intent) =
    (intent.getSerializableExtra(PushMessageHelper.KEY_MESSAGE) as? MiPushMessage)?.extra
}

class XiaomiReceiver : PushMessageReceiver() {
  override fun onReceiveRegisterResult(context: Context, message: MiPushCommandMessage) {
    if (message.command != MiPushClient.COMMAND_REGISTER || message.resultCode != ErrorCode.SUCCESS.toLong()) return
    message.commandArguments?.firstOrNull()?.let { FlutterPushPlusPlugin.emitToken("XIAOMI", it) }
  }

  override fun onReceivePassThroughMessage(context: Context, message: MiPushMessage) {
    FlutterPushPlusPlugin.emitMessage(message.extra.orEmpty(), message.title, message.description)
  }
}
