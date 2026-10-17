package com.will.flutter_push_plus

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** 安卓端：选通道、拿令牌、把推送点击和前台消息交给 Dart；弹通知统一在 Dart 侧。 */
class FlutterPushPlusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var token: Map<String, String>? = null
  /** 冷启动由通知拉起时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。 */
  private var pendingOpen: Map<String, Any>? = null

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

  private val prefs get() = context.getSharedPreferences("flutter_push_plus", Context.MODE_PRIVATE)

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init" -> {
        call.argument<Number>("backgroundHandle")?.let { prefs.edit().putLong("backgroundHandle", it.toLong()).apply() }
          ?: prefs.edit().remove("backgroundHandle").apply()
        PushRouter.pick(context)?.also { v ->
          Log.i(TAG, "channel ${v.channel}")
          v.register(context) { emitToken(v.channel, it) } // 各家回调线程不定，统一切回主线程
        } ?: Log.w(TAG, "no push channel available")
        val icon = context.pushConfig("icon")
          ?.takeIf { context.resources.getIdentifier(it, "drawable", context.packageName) != 0 }
        result.success(
          mapOf(
            "channelId" to (context.pushConfig("channelId") ?: "push"),
            "channelName" to (context.pushConfig("channelName") ?: "Push"),
            "icon" to icon,
          ),
        )
      }
      "getToken" -> result.success(token)
      "takeLaunchOpen" -> {
        result.success(pendingOpen)
        pendingOpen = null
      }
      "getBackgroundHandle" -> result.success(prefs.getLong("backgroundHandle", 0L).takeIf { it != 0L })
      "openNotificationSettings" -> {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    binding.addOnNewIntentListener(this)
    pendingOpen = takeClick(binding.activity.intent)
  }

  override fun onNewIntent(intent: Intent): Boolean {
    val open = takeClick(intent) ?: return false
    channel.invokeMethod("open", open, object : MethodChannel.Result {
      override fun success(result: Any?) {
        if (result != true) pendingOpen = open
      }
      override fun error(code: String, message: String?, details: Any?) { pendingOpen = open }
      override fun notImplemented() { pendingOpen = open }
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
  private fun takeClick(intent: Intent?): Map<String, Any>? {
    val extras = intent?.extras ?: return null
    // 本地通知的点击由 flutter_local_notifications 自己投递
    if (extras.containsKey("notificationId")) return null
    // 冷启动时 init 还没选通道，所以每个编进来的厂商都试一遍（小米的消息是序列化对象，通用规则取不到）
    val data = PushRouter.compiled.values.firstNotNullOfOrNull { it.extractClick(intent) }
      ?: extras.keySet().filterNot { key -> key in IGNORED_KEYS || IGNORED_PREFIXES.any(key::startsWith) }
        .mapNotNull { key -> (extras.get(key) as? String)?.let { key to it } }
        .toMap()
    if (data.isEmpty()) return null
    intent.replaceExtras(Bundle())
    return mapOf("data" to data)
  }

  /** 华为、荣耀的令牌会从主动获取和 onNewToken 各来一次，相同的不重复通知。 */
  private fun emitTokenOnMain(name: String, value: String) {
    val next = mapOf("channel" to name, "token" to value)
    if (next == token) return
    token = next
    channel.invokeMethod("token", next)
  }

  companion object {
    private const val TAG = "flutter_push_plus"
    private val IGNORED_PREFIXES = listOf("google.", "gcm.", "android.", "androidx.", "_push_", "vivo_push_")
    private val IGNORED_KEYS = setOf("from", "collapse_key")
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var instance: FlutterPushPlusPlugin? = null

    /** 各厂商 Service/Receiver 收到新令牌时调用（任意线程）。 */
    fun emitToken(channel: String, token: String) = main.post { instance?.emitTokenOnMain(channel, token) }

    /** 前台收到远程推送（FCM 前台、各家透传）时调用；要不要弹由 Dart 按 showInForeground 决定。 */
    fun emitMessage(data: Map<String, String>, title: String?, body: String?) = main.post {
      instance?.channel?.invokeMethod("message", mapOf("title" to title, "body" to body, "data" to data))
    }
  }
}
