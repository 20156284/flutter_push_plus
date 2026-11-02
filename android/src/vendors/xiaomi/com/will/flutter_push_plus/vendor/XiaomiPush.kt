package com.will.flutter_push_plus.vendor

import android.content.Context
import android.content.Intent
import android.util.Log
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.TAG
import com.will.flutter_push_plus.pushConfig
import com.xiaomi.mipush.sdk.ErrorCode
import com.xiaomi.mipush.sdk.MiPushClient
import com.xiaomi.mipush.sdk.MiPushCommandMessage
import com.xiaomi.mipush.sdk.MiPushMessage
import com.xiaomi.mipush.sdk.PushMessageHelper
import com.xiaomi.mipush.sdk.PushMessageReceiver

private const val CHANNEL = "XIAOMI"

/** 小米推送：小米 / 红米 / POCO。服务端用 notify_effect=1 打开应用，自定义字段放 extra.*。 */
internal class XiaomiPush : PushVendor {
  override val channel = CHANNEL

  override fun isSupported(context: Context) = true

  override fun register(context: Context, onToken: (String?) -> Unit) {
    onToken(MiPushClient.getRegId(context))
    MiPushClient.registerPush(context, context.pushConfig("xiaomi.appId"), context.pushConfig("xiaomi.appKey"))
  }

  /** 预定义点击（notify_effect）不回调 Receiver，消息整包序列化在启动 Intent 里；发送控制字段不算业务 data。 */
  @Suppress("DEPRECATION")
  override fun extractClick(intent: Intent) =
    (intent.getSerializableExtra(PushMessageHelper.KEY_MESSAGE) as? MiPushMessage)?.extra
      ?.also { intent.removeExtra(PushMessageHelper.KEY_MESSAGE) }
      ?.minus(setOf("notify_effect", "channel_id"))
}

internal class XiaomiReceiver : PushMessageReceiver() {
  override fun onReceiveRegisterResult(context: Context, message: MiPushCommandMessage) {
    if (message.command != MiPushClient.COMMAND_REGISTER) return
    if (message.resultCode != ErrorCode.SUCCESS.toLong()) {
      Log.w(TAG, "XIAOMI register failed: ${message.resultCode} ${message.reason}")
      return
    }
    FlutterPushPlusPlugin.emitToken(CHANNEL, message.commandArguments?.firstOrNull())
  }

  /** 透传主体（服务端 payload）放进 data['payload']，与 Dart 侧约定一致。 */
  override fun onReceivePassThroughMessage(context: Context, message: MiPushMessage) {
    val data = message.extra.orEmpty() + listOfNotNull(message.content?.takeIf { it.isNotEmpty() }?.let { "payload" to it })
    FlutterPushPlusPlugin.emitMessage(data, message.title, message.description)
  }
}
