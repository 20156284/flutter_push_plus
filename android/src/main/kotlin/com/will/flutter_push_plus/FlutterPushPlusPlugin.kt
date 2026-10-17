package com.will.flutter_push_plus

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** 安卓端：FCM 令牌与通知点击。厂商通道（华为/小米/OPPO/vivo/荣耀）按同样形状逐家加。 */
class FlutterPushPlusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var token: String? = null
  /** 冷启动由通知拉起时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。 */
  private var pendingOpen: Map<String, String>? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "flutter_push_plus")
    channel.setMethodCallHandler(this)
    instance = this
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    if (instance === this) instance = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init" -> {
        startFcm(call.arguments as? Map<*, *>)
        result.success(null)
      }
      "getToken" -> result.success(token?.let { mapOf("channel" to "FCM", "token" to it) })
      "takeLaunchOpen" -> {
        result.success(pendingOpen)
        pendingOpen = null
      }
      else -> result.notImplemented()
    }
  }

  /** 传了 [options] 就用它初始化 Firebase，否则退回 google-services.json；两者都没有则不启用 FCM。 */
  private fun startFcm(options: Map<*, *>?) {
    if (FirebaseApp.getApps(context).isEmpty()) {
      val app = if (options == null) FirebaseApp.initializeApp(context) else FirebaseApp.initializeApp(
        context,
        FirebaseOptions.Builder()
          .setApiKey(options["apiKey"] as String)
          .setApplicationId(options["appId"] as String)
          .setProjectId(options["projectId"] as String)
          .setGcmSenderId(options["senderId"] as String)
          .build(),
      )
      app ?: return
    }
    FirebaseMessaging.getInstance().token.addOnSuccessListener(::onToken)
  }

  fun onToken(value: String) {
    token = value
    channel.invokeMethod("token", mapOf("channel" to "FCM", "token" to value))
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addOnNewIntentListener(this)
    pendingOpen = pushData(binding.activity.intent)
  }

  override fun onNewIntent(intent: Intent): Boolean {
    val data = pushData(intent) ?: return false
    channel.invokeMethod("open", data, object : MethodChannel.Result {
      override fun success(result: Any?) {
        if (result != true) pendingOpen = data
      }
      override fun error(code: String, message: String?, details: Any?) { pendingOpen = data }
      override fun notImplemented() { pendingOpen = data }
    })
    return true
  }

  override fun onDetachedFromActivityForConfigChanges() {}
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    binding.addOnNewIntentListener(this)
  override fun onDetachedFromActivity() {}

  companion object {
    @Volatile
    internal var instance: FlutterPushPlusPlugin? = null

    /** FCM 通知被点时系统把 data 塞进启动 Intent 的 extras，带 google.message_id 才算推送。 */
    private fun pushData(intent: Intent?): Map<String, String>? {
      val extras = intent?.extras ?: return null
      if (!extras.containsKey("google.message_id")) return null
      return extras.keySet()
        .filterNot { it.startsWith("google.") || it.startsWith("gcm.") || it == "from" || it == "collapse_key" }
        .associateWith { extras.get(it)?.toString() ?: "" }
    }

    internal fun postToken(value: String) =
      Handler(Looper.getMainLooper()).post { instance?.onToken(value) }
  }
}
