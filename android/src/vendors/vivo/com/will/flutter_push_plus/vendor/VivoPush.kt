package com.will.flutter_push_plus.vendor

import android.content.Context
import android.util.Log
import com.vivo.push.PushClient
import com.vivo.push.PushConfig
import com.vivo.push.listener.IPushQueryActionListener
import com.vivo.push.sdk.OpenClientPushMessageReceiver
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.TAG

private const val CHANNEL = "VIVO"

/** vivo 推送：vivo / iQOO。服务端 skipType=1，clientCustomMap 的键值会平铺进启动 Intent。 */
internal class VivoPush : PushVendor {
  override val channel = CHANNEL

  /** 插件 init 由宿主在用户同意隐私政策之后调用，故此处声明已同意。 */
  override fun isSupported(context: Context): Boolean {
    val client = PushClient.getInstance(context)
    client.initialize(PushConfig.Builder().agreePrivacyStatement(true).build())
    return client.isSupport
  }

  override fun register(context: Context, onToken: (String?) -> Unit) {
    val client = PushClient.getInstance(context)
    client.turnOnPush { state ->
      if (state != 0) {
        Log.w(TAG, "VIVO turnOnPush failed: $state")
        return@turnOnPush
      }
      client.getRegId(object : IPushQueryActionListener {
        override fun onSuccess(regId: String?) = onToken(regId)

        override fun onFail(code: Int?) {
          Log.w(TAG, "VIVO getRegId failed: $code")
        }
      })
    }
  }
}

internal class VivoReceiver : OpenClientPushMessageReceiver() {
  override fun onReceiveRegId(context: Context?, regId: String?) {
    FlutterPushPlusPlugin.emitToken(CHANNEL, regId)
  }
}
