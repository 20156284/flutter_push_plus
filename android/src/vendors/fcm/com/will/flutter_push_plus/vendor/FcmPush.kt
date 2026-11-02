package com.will.flutter_push_plus.vendor

import android.content.Context
import android.util.Log
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.will.flutter_push_plus.FlutterPushPlusPlugin
import com.will.flutter_push_plus.PushVendor
import com.will.flutter_push_plus.TAG
import com.will.flutter_push_plus.pushConfig

private const val CHANNEL = "FCM"

/** 谷歌 FCM：三星、Pixel 等海外机型及国产通道都不可用时的兜底。 */
internal class FcmPush : PushVendor {
  override val channel = CHANNEL

  /** 没有谷歌服务（多数国行机）拿不到令牌；gradle.properties 填了四项就用它初始化，否则走 google-services.json。 */
  override fun isSupported(context: Context): Boolean {
    if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS) return false
    if (FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME }) return true
    val appId = context.pushConfig("fcm.appId") ?: return FirebaseApp.initializeApp(context) != null
    FirebaseApp.initializeApp(
      context,
      FirebaseOptions.Builder()
        .setApplicationId(appId)
        .setApiKey(context.pushConfig("fcm.apiKey")!!)
        .setProjectId(context.pushConfig("fcm.projectId"))
        .setGcmSenderId(context.pushConfig("fcm.senderId"))
        .build(),
    )
    return true
  }

  override fun register(context: Context, onToken: (String?) -> Unit) {
    val messaging = FirebaseMessaging.getInstance()
    // manifest 关了自动初始化，等宿主调 init（用户已同意隐私政策）才打开
    messaging.isAutoInitEnabled = true
    messaging.token
      .addOnSuccessListener(onToken)
      .addOnFailureListener { Log.w(TAG, "FCM getToken failed", it) }
  }
}

internal class FcmService : FirebaseMessagingService() {
  override fun onNewToken(token: String) {
    FlutterPushPlusPlugin.emitToken(CHANNEL, token)
  }

  /** 通知消息只有 App 在前台才会走到这里（后台由系统直接展示），数据消息只要进程活着都会到。 */
  override fun onMessageReceived(message: RemoteMessage) {
    val notification = message.notification
    FlutterPushPlusPlugin.emitMessage(message.data, notification?.title, notification?.body, notification?.channelId)
  }
}
