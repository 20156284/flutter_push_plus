package com.will.flutter_push_plus

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/** 一家推送通道。实现类放在 src/vendors/<厂商>/，只有宿主配置了该厂商才会编进包。 */
interface PushVendor {
  /** 上报给服务端的通道名：FCM / HUAWEI / HONOR / XIAOMI / OPPO / VIVO */
  val channel: String

  /** 本机能否用这家通道（系统服务在不在、ROM 版本够不够）。 */
  fun isSupported(context: Context): Boolean

  /** 注册并回调令牌；令牌轮换时由各家的 Service/Receiver 走 [FlutterPushPlusPlugin.emitToken]。 */
  fun register(context: Context, onToken: (String) -> Unit)

  /** 点击通知拉起 App 时，从 Intent 取出推送自定义字段；不是自家的推送返回 null。 */
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
        runCatching { vendor.isSupported(context) }
          .onFailure { Log.w("flutter_push_plus", "${vendor.channel} unavailable", it) }
          .getOrDefault(false)
          .also { if (!it) Log.i("flutter_push_plus", "${vendor.channel} not supported on this device") }
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

/** 读 gradle.properties 里 pushPlus.* 生成的 meta-data（值带 pp: 前缀防止被解析成数字）。 */
internal fun Context.pushConfig(key: String): String? {
  val meta = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA).metaData
  return meta?.getString("pushplus.$key")?.removePrefix("pp:")
}
