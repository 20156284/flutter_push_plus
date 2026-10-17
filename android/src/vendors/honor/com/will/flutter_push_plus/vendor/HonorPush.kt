package com.will.flutter_push_plus.vendor

import android.content.Context
import com.hihonor.push.sdk.HonorMessageService
import com.hihonor.push.sdk.HonorPushCallback
import com.hihonor.push.sdk.HonorPushClient
import com.hihonor.push.sdk.HonorPushDataMsg
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import org.json.JSONObject

/** 荣耀推送：2020 年后的荣耀机型（MagicOS 4.0+）。 */
class HonorPush : PushVendor {
  override val channel = "HONOR"

  override fun isSupported(context: Context) = HonorPushClient.getInstance().checkSupportHonorPush(context)

  override fun register(context: Context, onToken: (String) -> Unit) {
    HonorPushClient.getInstance().init(context, true)
    HonorPushClient.getInstance().getPushToken(object : HonorPushCallback<String> {
      override fun onSuccess(token: String?) {
        if (!token.isNullOrEmpty()) onToken(token)
      }

      override fun onFailure(code: Int, message: String?) {}
    })
  }
}

class HonorService : HonorMessageService() {
  override fun onNewToken(token: String?) {
    if (!token.isNullOrEmpty()) FlutterPushPlusPlugin.emitToken("HONOR", token)
  }

  /** 透传消息，进程不在时会被系统拦掉，只作前台补充。 */
  override fun onMessageReceived(message: HonorPushDataMsg?) {
    val json = runCatching { JSONObject(message?.data.orEmpty()) }.getOrNull() ?: return
    FlutterPushPlusPlugin.emitMessage(json.keys().asSequence().associateWith { json.optString(it) }, null, null)
  }
}
