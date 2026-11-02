package com.will.flutter_push_plus.vendor

import android.content.Context
import android.util.Log
import com.huawei.hms.aaid.HmsInstanceId
import com.huawei.hms.api.ConnectionResult
import com.huawei.hms.api.HuaweiApiAvailability
import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.TAG
import com.will.flutter_push_plus.pushConfig
import kotlin.concurrent.thread

private const val CHANNEL = "HUAWEI"

/** 华为 HMS Push Kit：华为机型与 2020 年拆分前的荣耀老机型。 */
internal class HuaweiPush : PushVendor {
  override val channel = CHANNEL

  override fun isSupported(context: Context) =
    HuaweiApiAvailability.getInstance().isHuaweiMobileServicesAvailable(context) == ConnectionResult.SUCCESS

  /** getToken 是同步网络调用，主线程调会抛 907122050；返回空时令牌改由 onNewToken 送达。 */
  override fun register(context: Context, onToken: (String?) -> Unit) {
    thread {
      runCatching { HmsInstanceId.getInstance(context).getToken(context.pushConfig("huawei.appId"), "HCM") }
        .onSuccess(onToken)
        .onFailure { Log.w(TAG, "HUAWEI getToken failed", it) }
    }
  }
}

internal class HuaweiService : HmsMessageService() {
  override fun onNewToken(token: String?) {
    FlutterPushPlusPlugin.emitToken(CHANNEL, token)
  }

  override fun onTokenError(exception: Exception?) {
    Log.w(TAG, "HUAWEI token error", exception)
  }

  /** dataOfMap 遇到非 JSON 返回空，原文放进 payload，与荣耀、小米一致。 */
  override fun onMessageReceived(message: RemoteMessage?) {
    message ?: return
    val data = message.dataOfMap.orEmpty().ifEmpty {
      message.data?.takeIf { it.isNotEmpty() }?.let { mapOf("payload" to it) }.orEmpty()
    }
    FlutterPushPlusPlugin.emitMessage(data, message.notification?.title, message.notification?.body)
  }
}
