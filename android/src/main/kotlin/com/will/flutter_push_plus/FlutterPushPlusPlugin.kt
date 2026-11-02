package com.will.flutter_push_plus

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/** 安卓端：选通道、拿令牌、把推送点击和收到的消息交给 Dart；弹通知统一在 Dart 侧。 */
class FlutterPushPlusPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
  PluginRegistry.NewIntentListener, ActivityPluginBinding.OnSaveInstanceStateListener {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activityBinding: ActivityPluginBinding? = null
  private var token: Map<String, String>? = null
  /** 冷启动由通知拉起时 Dart 还没挂处理器，先存着等 takeLaunchOpen 取走。 */
  private var pendingOpen: Map<String, Any>? = null
  private var reattached = false

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "flutter_push_plus")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    if (instance === this) instance = null
  }

  private fun prefs() = context.getSharedPreferences("flutter_push_plus", Context.MODE_PRIVATE)

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init" -> {
        // 只认调了 init 的主引擎：按钮回调会另起后台引擎并再注册一遍插件，不能把令牌和消息发过去
        instance = this
        // 重复 init 或热重启后 Dart 要重新拿到令牌
        token = null
        call.argument<Number>("backgroundHandle")?.let { prefs().edit().putLong("backgroundHandle", it.toLong()).apply() }
          ?: prefs().edit().remove("backgroundHandle").apply()
        PushRouter.pick(context)?.also { v ->
          Log.i(TAG, "channel ${v.channel}")
          // 推送注册失败不能拖垮本地通知和点击路由；各家回调线程不定，统一切回主线程
          runCatching { v.register(context) { emitToken(v.channel, it) } }
            .onFailure { Log.w(TAG, "${v.channel} register failed", it) }
        } ?: Log.w(TAG, "no push channel available")
        val res = context.resources
        val icon = context.iconRes().takeIf { it != 0 } ?: context.applicationInfo.icon
        result.success(
          mapOf(
            "channelId" to context.pushConfig("channelId"),
            "channelName" to context.pushConfig("channelName"),
            "icon" to "@${res.getResourceTypeName(icon)}/${res.getResourceEntryName(icon)}",
          ),
        )
      }
      "getToken" -> result.success(token)
      "takeLaunchOpen" -> {
        result.success(pendingOpen)
        pendingOpen = null
      }
      "getBackgroundHandle" -> result.success(prefs().getLong("backgroundHandle", 0L).takeIf { it != 0L })
      else -> result.notImplemented()
    }
  }

  private fun attach(binding: ActivityPluginBinding) {
    activityBinding = binding
    binding.addOnNewIntentListener(this)
    binding.addOnSaveStateListener(this)
  }

  private fun detach() {
    activityBinding?.removeOnNewIntentListener(this)
    activityBinding?.removeOnSaveStateListener(this)
    activityBinding = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    reattached = false
    attach(binding)
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

  override fun onSaveInstanceState(bundle: Bundle) {}

  /** 进程被回收后系统用原始 Intent 重建页面，这次点击早已投递过；缓存引擎配置变更时引擎还在，待取的点击要留着。 */
  override fun onRestoreInstanceState(bundle: Bundle?) {
    if (bundle != null && !reattached) pendingOpen = null
  }

  override fun onDetachedFromActivityForConfigChanges() = detach()
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    reattached = true
    attach(binding)
  }
  override fun onDetachedFromActivity() = detach()

  /**
   * 各家「点击打开应用」都把自定义字段平铺进启动 Intent 的 extras；取完只清用掉的键，其余留给宿主。
   * extras 可被其他 App 塞入本进程没有的序列化类，反序列化失败按不是推送处理。
   */
  private fun takeClick(intent: Intent?): Map<String, Any>? {
    intent ?: return null
    return runCatching { readClick(intent) }
      .onFailure { Log.w(TAG, "read click extras failed", it) }
      .getOrNull()
  }

  private fun readClick(intent: Intent): Map<String, Any>? {
    val extras = intent.extras ?: return null
    // 从最近任务恢复会带着原始 Intent 重建页面，这次点击早已投递过
    if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
    // 本地通知的点击由 flutter_local_notifications 自己投递
    if (intent.action in LOCAL_NOTIFICATION_ACTIONS) return null
    // 冷启动时 init 还没选通道，所以每个编进来的厂商都试一遍（小米的消息是序列化对象，通用规则取不到）
    val data = PushRouter.compiled.values.firstNotNullOfOrNull { it.extractClick(intent) }
      ?.filterKeys { !isReserved(it) }
      ?: genericClick(intent, extras)
    return if (data.isEmpty()) null else mapOf("data" to data)
  }

  /** 无厂商标记时按「有字符串 extras 即推送」判断；带 URI 的是深链，交给宿主。 */
  private fun genericClick(intent: Intent, extras: Bundle): Map<String, String> {
    if (intent.data != null) return emptyMap()
    return extras.keySet().filterNot(::isReserved)
      .mapNotNull { key -> extras.getString(key)?.let { key to it } }
      .toMap()
      .also { it.keys.forEach(intent::removeExtra) }
  }

  private fun isReserved(key: String) = key in IGNORED_KEYS || IGNORED_PREFIXES.any(key::startsWith)

  /** 华为、荣耀的令牌会从主动获取和 onNewToken 各来一次，相同的不重复通知。 */
  private fun emitTokenOnMain(name: String, value: String) {
    val next = mapOf("channel" to name, "token" to value)
    if (next == token) return
    token = next
    channel.invokeMethod("token", next)
  }

  companion object {
    private val LOCAL_NOTIFICATION_ACTIONS = setOf("SELECT_NOTIFICATION", "SELECT_FOREGROUND_NOTIFICATION")
    private val IGNORED_PREFIXES = listOf("google.", "gcm.", "android.", "androidx.", "_push_", "vivo_push_")
    // 后几个是 Flutter 启动页自己的 extras 和 flutter run 带的启动参数
    private val IGNORED_KEYS = setOf(
      "from", "collapse_key", "route", "cached_engine_id", "cached_engine_group_id",
      "dart_entrypoint", "background_mode", "dart-flags", "trace-allowlist", "trace-skia-allowlist", "trace-to-file",
    )
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var instance: FlutterPushPlusPlugin? = null

    /** 各厂商 Service/Receiver 收到新令牌时调用（任意线程）；空令牌忽略。 */
    internal fun emitToken(channel: String, token: String?) {
      if (token.isNullOrEmpty()) return
      main.post { instance?.emitTokenOnMain(channel, token) }
    }

    /** 引擎活着时收到远程推送（FCM、各家透传，含后台）调用；要不要弹由 Dart 按 showInForeground 决定。 */
    internal fun emitMessage(data: Map<String, String>, title: String?, body: String?, channelId: String? = null) {
      main.post {
        instance?.channel?.invokeMethod(
          "message",
          mapOf(
            "title" to title?.takeIf { it.isNotEmpty() },
            "body" to body?.takeIf { it.isNotEmpty() },
            "data" to data,
            "channelId" to channelId,
          ),
        ) ?: Log.d(TAG, "message dropped: init not called")
      }
    }
  }
}
