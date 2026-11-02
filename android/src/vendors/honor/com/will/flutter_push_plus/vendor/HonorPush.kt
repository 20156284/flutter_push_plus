package com.will.flutter_push_plus.vendor

import android.content.Context
import android.util.Log
import com.hihonor.push.sdk.HonorMessageService
import com.hihonor.push.sdk.HonorPushCallback
import com.hihonor.push.sdk.HonorPushClient
import com.hihonor.push.sdk.HonorPushDataMsg
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.TAG
import org.json.JSONObject

private const val CHANNEL = "HONOR"

/** 荣耀推送：2020 年后的荣耀机型（MagicOS 4.0+）。 */
internal class HonorPush : PushVendor {
  override val channel = CHANNEL

  override fun isSupported(context: Context) = HonorPushClient.getInstance().checkSupportHonorPush(context)

  override fun register(context: Context, onToken: (String?) -> Unit) {
    HonorPushClient.getInstance().init(context, true)
    HonorPushClient.getInstance().getPushToken(object : HonorPushCallback<String> {
      override fun onSuccess(token: String?) = onToken(token)

      override fun onFailure(code: Int, message: String?) {
        Log.w(TAG, "HONOR getPushToken failed: $code $message")
      }
    })
  }
}

internal class HonorService : HonorMessageService() {
  override fun onNewToken(token: String?) {
    FlutterPushPlusPlugin.emitToken(CHANNEL, token)
  }

  /** 透传消息，进程不在时会被系统拦掉，只作前台补充；不是 JSON 时原文放进 payload。 */
  override fun onMessageReceived(message: HonorPushDataMsg?) {
    val raw = message?.data?.takeIf { it.isNotEmpty() } ?: return
    val data = runCatching { JSONObject(raw) }
      .map { json -> json.keys().asSequence().associateWith { json.optString(it) } }
      .getOrElse { mapOf("payload" to raw) }
    FlutterPushPlusPlugin.emitMessage(data, null, null)
  }
}
