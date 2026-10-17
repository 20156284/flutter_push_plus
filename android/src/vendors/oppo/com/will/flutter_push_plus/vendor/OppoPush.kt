package com.will.flutter_push_plus.vendor

import android.content.Context
import com.heytap.msp.push.HeytapPushManager
import com.heytap.msp.push.callback.ICallBackResultService
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.pushConfig

/** OPPO 推送：OPPO / 一加 / 真我（ColorOS 3.1+）。服务端 action_parameters 的键值会平铺进启动 Intent。 */
class OppoPush : PushVendor {
  override val channel = "OPPO"

  override fun isSupported(context: Context): Boolean {
    HeytapPushManager.init(context, false)
    return HeytapPushManager.isSupportPush(context)
  }

  override fun register(context: Context, onToken: (String) -> Unit) {
    HeytapPushManager.register(
      context,
      context.pushConfig("oppo.appKey"),
      context.pushConfig("oppo.appSecret"),
      object : ICallBackResultService {
        override fun onRegister(code: Int, registerId: String?, pkg: String?, miniPkg: String?) {
          if (code == 0 && !registerId.isNullOrEmpty()) onToken(registerId)
        }

        override fun onUnRegister(code: Int, pkg: String?, miniPkg: String?) {}
        override fun onSetPushTime(code: Int, result: String?) {}
        override fun onGetPushStatus(code: Int, status: Int) {}
        override fun onGetNotificationStatus(code: Int, status: Int) {}
        override fun onError(code: Int, message: String?, pkg: String?, miniPkg: String?) {}
      },
    )
  }
}
