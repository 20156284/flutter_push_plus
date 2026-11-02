package com.will.flutter_push_plus

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

internal const val TAG = "flutter_push_plus"

/** 一家推送通道。实现类放在 src/vendors/<厂商>/，只有宿主配置了该厂商才会编进包。 */
internal interface PushVendor {
  /** 上报给服务端的通道名：FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO */
  val channel: String

  /** 本机能否用这家通道（系统服务在不在、ROM 版本够不够）。 */
  fun isSupported(context: Context): Boolean

  /** 注册并回调令牌；令牌轮换时由各家的 Service/Receiver 走 [FlutterPushPlusPlugin.emitToken]。 */
  fun register(context: Context, onToken: (String?) -> Unit)

  /** 点击通知拉起 App 时，从 Intent 取出推送自定义字段并清掉；不是自家的推送返回 null。 */
  fun extractClick(intent: Intent): Map<String, String>? = null
}

internal object PushRouter {
  private val NAMES = listOf("Honor", "Huawei", "Xiaomi", "Oppo", "Vivo", "Fcm")

  /** 编进包的所有厂商（只构造不初始化，不触发隐私合规问题）。 */
  val compiled: Map<String, PushVendor> by lazy { NAMES.mapNotNull { name -> load(name)?.let { name to it } }.toMap() }

  /** 按品牌排优先级，任何一家没编进来或本机不支持都往后退，最后兜底 FCM。 */
  fun pick(context: Context): PushVendor? {
    val brands = when (Build.MANUFACTURER.lowercase()) {
      "honor" -> listOf("Honor", "Huawei")
      "huawei" -> listOf("Huawei")
      "xiaomi", "redmi", "poco" -> listOf("Xiaomi")
      "oppo", "oneplus", "realme" -> listOf("Oppo")
      "vivo", "iqoo" -> listOf("Vivo")
      else -> emptyList()
    }
    return (brands + "Fcm").firstNotNullOfOrNull { name ->
      compiled[name]?.takeIf { vendor ->
        runCatching { vendor.isSupported(context) }.fold(
          onSuccess = { supported ->
            if (!supported) Log.i(TAG, "${vendor.channel} not supported on this device")
            supported
          },
          onFailure = {
            Log.w(TAG, "${vendor.channel} unavailable", it)
            false
          },
        )
      }
    }
  }

  private fun load(name: String): PushVendor? = try {
    Class.forName("com.will.flutter_push_plus.vendor.${name}Push")
      .getDeclaredConstructor().newInstance() as PushVendor
  } catch (_: ClassNotFoundException) {
    null
  }
}

private fun Context.pushMeta() = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA).metaData

/** 读 gradle.properties 里 pushPlus.* 生成的 meta-data（值带 pp: 前缀防止被解析成数字）。 */
internal fun Context.pushConfig(key: String): String? = pushMeta()?.getString("pushplus.$key")?.removePrefix("pp:")

/** 通知小图标的资源 id，没配为 0；manifest 直接引用资源，release 才不会被裁掉。 */
internal fun Context.iconRes(): Int = pushMeta()?.getInt("pushplus.iconRes") ?: 0
