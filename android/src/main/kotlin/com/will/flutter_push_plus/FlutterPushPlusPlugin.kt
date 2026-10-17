package com.will.flutter_push_plus

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class FlutterPushPlusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var vendor: PushVendor? = null
  private var token: Map<String, String>? = null
  private var showForeground = true
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
        showForeground = call.argument<Boolean>("showForeground") ?: true
        createChannel()
        vendor = PushRouter.pick(context)?.also { v ->
          Log.i(TAG, "channel ${v.channel}")
          v.register(context) { emitToken(v.channel, it) }
        } ?: null.also { Log.w(TAG, "no push channel available") }
        result.success(mapOf("channelId" to channelId, "channelName" to channelName))
      }
      "getToken" -> result.success(token)
      "takeLaunchOpen" -> {
        result.success(pendingOpen)
        pendingOpen = null
      }
      "openNotificationSettings" -> {
        context.startActivity(
          Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private val channelId get() = context.pushConfig("channelId") ?: "push"
  private val channelName get() = context.pushConfig("channelName") ?: "Push"

  /** OPPO、小米等要求通知渠道 ID 与服务端下发的 channel_id 一致，否则 Android 8+ 不显示。 */
  private fun createChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    context.getSystemService(NotificationManager::class.java).createNotificationChannel(
      NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_HIGH),
    )
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addOnNewIntentListener(this)
    pendingOpen = takeClick(binding.activity.intent)
  }

  override fun onNewIntent(intent: Intent): Boolean {
    val data = takeClick(intent) ?: return false
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

  /**
   * 各家「点击打开应用」都把自定义字段平铺进启动 Intent 的 extras；取完清掉，防止页面重建时重复投递。
   * ponytail: 无厂商标记时按「有字符串 extras 即推送」判断，宿主自己往启动页塞字符串 extras 会误判。
   */
  private fun takeClick(intent: Intent?): Map<String, String>? {
    intent ?: return null
    val data = vendor?.extractClick(intent) ?: intent.extras?.let { extras ->
      extras.keySet().filterNot { key -> key in IGNORED_KEYS || IGNORED_PREFIXES.any(key::startsWith) }
        .mapNotNull { key -> (extras.get(key) as? String)?.let { key to it } }
        .toMap()
    }
    if (data.isNullOrEmpty()) return null
    intent.replaceExtras(Bundle())
    return data
  }

  private fun emitToken(name: String, value: String) {
    token = mapOf("channel" to name, "token" to value)
    channel.invokeMethod("token", token)
  }

  private fun onMessage(data: Map<String, String>, title: String?, body: String?) {
    channel.invokeMethod("message", data + listOfNotNull(title?.let { "title" to it }, body?.let { "body" to it }))
    if (!showForeground || (title == null && body == null)) return
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
    data.forEach { (k, v) -> launch.putExtra(k, v) }
    val icon = context.pushConfig("icon")
      ?.let { context.resources.getIdentifier(it, "drawable", context.packageName) }
      ?.takeIf { it != 0 } ?: context.applicationInfo.icon
    val id = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
    runCatching {
      NotificationManagerCompat.from(context).notify(
        id,
        NotificationCompat.Builder(context, channelId)
          .setSmallIcon(icon)
          .setContentTitle(title)
          .setContentText(body)
          .setAutoCancel(true)
          .setPriority(NotificationCompat.PRIORITY_HIGH)
          .setContentIntent(
            PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
          )
          .build(),
      )
    }.onFailure { Log.w(TAG, "foreground notify failed", it) } // 没有通知权限时会抛 SecurityException
  }

  companion object {
    private const val TAG = "flutter_push_plus"
    private val IGNORED_PREFIXES = listOf("google.", "gcm.", "android.", "androidx.", "_push_", "vivo_push_")
    private val IGNORED_KEYS = setOf("from", "collapse_key")
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var instance: FlutterPushPlusPlugin? = null

    /** 各厂商 Service/Receiver 收到新令牌时调用（任意线程）。 */
    fun emitToken(channel: String, token: String) = main.post { instance?.emitToken(channel, token) }

    /** 前台收到远程推送（FCM 前台、各家透传）时调用；有标题正文则代为弹系统通知。 */
    fun emitMessage(data: Map<String, String>, title: String?, body: String?) =
      main.post { instance?.onMessage(data, title, body) }
  }
}
