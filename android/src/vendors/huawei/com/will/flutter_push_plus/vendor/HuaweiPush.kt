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
import com.will.flutter_push_plus.pushConfig
import kotlin.concurrent.thread

/** 华为 HMS Push Kit：华为机型与 2020 年拆分前的荣耀老机型。 */
class HuaweiPush : PushVendor {
  override val channel = "HUAWEI"

  override fun isSupported(context: Context) =
    HuaweiApiAvailability.getInstance().isHuaweiMobileServicesAvailable(context) == ConnectionResult.SUCCESS

  /** getToken 是同步网络调用，主线程调会抛 907122050；返回空时令牌改由 onNewToken 送达。 */
  override fun register(context: Context, onToken: (String) -> Unit) {
    thread {
      runCatching { HmsInstanceId.getInstance(context).getToken(context.pushConfig("huawei.appId"), "HCM") }
        .onSuccess { if (!it.isNullOrEmpty()) onToken(it) }
        .onFailure { Log.w("flutter_push_plus", "HUAWEI getToken failed", it) }
    }
  }
}

class HuaweiService : HmsMessageService() {
  override fun onNewToken(token: String?) {
    if (!token.isNullOrEmpty()) FlutterPushPlusPlugin.emitToken("HUAWEI", token)
  }

  override fun onMessageReceived(message: RemoteMessage?) {
    message ?: return
    FlutterPushPlusPlugin.emitMessage(message.dataOfMap.orEmpty(), message.notification?.title, message.notification?.body)
  }
}
