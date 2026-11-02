group = "com.will.flutter_push_plus"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

/** gradle.properties 按 ISO-8859-1 读入，直接写的中文要还原成 UTF-8；`\uXXXX` 写法与纯 ASCII 不受影响。 */
fun utf8(raw: String): String {
    if (raw.any { it.code > 0xFF }) return raw
    return String(raw.toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8).takeUnless { '�' in it } ?: raw
}

/** 宿主 android/gradle.properties 里的 pushPlus.* 配置（已做 XML 转义）；没填的厂商整个不编进包。 */
fun prop(key: String) = (findProperty("pushPlus.$key") as String?)?.let(::utf8)?.trim()?.takeIf { it.isNotEmpty() }
    ?.replace("&", "&amp;")?.replace("\"", "&quot;")?.replace("<", "&lt;")

/** 小米、OPPO 官方只给 aar，由宿主放进 android/app/libs/。 */
fun hostAar(prefix: String) = rootProject.file("app/libs").listFiles()
    ?.firstOrNull { it.name.startsWith(prefix) && it.name.endsWith(".aar") }

val xiaomiAar = hostAar("MiPush_SDK_Client")
val oppoAar = hostAar("com.heytap.msp")

class Vendor(
    val name: String,
    val enabled: Boolean,
    val manifest: String = "",
    val permissions: List<String> = emptyList(),
    val queries: String = "",
    val repo: Pair<String, String>? = null,
    val dependencies: List<String> = emptyList(),
    val aar: File? = null,
    val proguard: Boolean = true,
)

/** 自家 meta-data 统一加前缀，防止纯数字的 ID 被当成整数解析丢精度。 */
fun meta(key: String) = """<meta-data android:name="pushplus.$key" android:value="pp:${prop(key)}" />"""

// 成对的键缺一个时厂商 SDK 只会静默失败，在构建期就报出来
listOf(
    listOf("fcm.appId", "fcm.apiKey", "fcm.projectId", "fcm.senderId"),
    listOf("xiaomi.appId", "xiaomi.appKey"),
    listOf("oppo.appKey", "oppo.appSecret"),
    listOf("vivo.appId", "vivo.apiKey"),
).forEach { keys ->
    val missing = keys.filter { prop(it) == null }
    if (missing.isNotEmpty() && missing.size < keys.size) {
        throw GradleException("flutter_push_plus: ${keys.joinToString { "pushPlus.$it" }} 要一起填，缺 ${missing.joinToString { "pushPlus.$it" }}")
    }
}
listOf("xiaomi.appId" to ("MiPush_SDK_Client" to xiaomiAar), "oppo.appKey" to ("com.heytap.msp" to oppoAar)).forEach { (key, aar) ->
    if (prop(key) != null && aar.second == null) {
        throw GradleException("flutter_push_plus: 填了 pushPlus.$key 还要把 ${aar.first}*.aar 放进 android/app/libs/")
    }
}

val channelId = prop("channelId") ?: "push"
val fcmIcon = prop("icon")?.let {
    """
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/$it" />"""
}.orEmpty()

val vendors = listOf(
    Vendor(
        "fcm",
        prop("fcm.appId") != null || rootProject.file("app/google-services.json").exists() ||
            rootProject.file("app/src").listFiles().orEmpty().any { File(it, "google-services.json").exists() },
        listOf("fcm.apiKey", "fcm.appId", "fcm.projectId", "fcm.senderId").filter { prop(it) != null }
            .joinToString("") { meta(it) } + """
        <!-- 用户同意隐私政策、调了 init 之后才生成令牌 -->
        <meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="$channelId" />$fcmIcon
        <service android:name=".vendor.FcmService" android:exported="false">
            <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter>
        </service>""",
        dependencies = listOf(
            "com.google.firebase:firebase-messaging:24.1.0",
            // 检测有无谷歌服务；firebase-messaging 只在运行期带它，编译期要显式声明（同版本）
            "com.google.android.gms:play-services-base:18.0.1",
        ),
        proguard = false,
    ),
    Vendor(
        "huawei", prop("huawei.appId") != null, """
        ${meta("huawei.appId")}
        <meta-data android:name="com.huawei.hms.client.appid" android:value="appid=${prop("huawei.appId")}" />
        <service android:name=".vendor.HuaweiService" android:exported="false">
            <intent-filter><action android:name="com.huawei.push.action.MESSAGING_EVENT" /></intent-filter>
        </service>""",
        repo = "https://developer.huawei.com/repo/" to """com\.huawei\..*""",
        dependencies = listOf("com.huawei.hms:push:6.13.0.301"),
    ),
    Vendor(
        "honor", prop("honor.appId") != null, """
        <meta-data android:name="com.hihonor.push.app_id" android:value="${prop("honor.appId")}" />
        <service android:name=".vendor.HonorService" android:exported="false">
            <intent-filter><action android:name="com.hihonor.push.action.MESSAGING_EVENT" /></intent-filter>
        </service>""",
        queries = """<intent><action android:name="com.hihonor.push.action.BIND_PUSH_SERVICE" /></intent>""",
        repo = "https://developer.honor.com/repo" to """com\.hihonor\..*""",
        dependencies = listOf("com.hihonor.mcs:push:10.0.39.302"),
    ),
    Vendor(
        "xiaomi", prop("xiaomi.appId") != null, """
        ${meta("xiaomi.appId")}${meta("xiaomi.appKey")}
        <receiver android:name=".vendor.XiaomiReceiver" android:exported="true">
            <intent-filter>
                <action android:name="com.xiaomi.mipush.RECEIVE_MESSAGE" />
                <action android:name="com.xiaomi.mipush.MESSAGE_ARRIVED" />
                <action android:name="com.xiaomi.mipush.ERROR" />
            </intent-filter>
        </receiver>""",
        aar = xiaomiAar,
    ),
    Vendor(
        "oppo", prop("oppo.appKey") != null, """
        ${meta("oppo.appKey")}${meta("oppo.appSecret")}
        <service android:name="com.heytap.msp.push.service.CompatibleDataMessageCallbackService"
            android:exported="true" android:permission="com.coloros.mcs.permission.SEND_MCS_MESSAGE">
            <intent-filter><action android:name="com.coloros.mcs.action.RECEIVE_MCS_MESSAGE" /></intent-filter>
        </service>
        <service android:name="com.heytap.msp.push.service.DataMessageCallbackService"
            android:exported="true" android:permission="com.heytap.mcs.permission.SEND_PUSH_MESSAGE">
            <intent-filter>
                <action android:name="com.heytap.mcs.action.RECEIVE_MCS_MESSAGE" />
                <action android:name="com.heytap.msp.push.RECEIVE_MCS_MESSAGE" />
            </intent-filter>
        </service>""",
        // RECIEVE 是 OPPO 官方的拼写
        permissions = listOf(
            "com.coloros.mcs.permission.RECIEVE_MCS_MESSAGE",
            "com.heytap.mcs.permission.RECIEVE_MCS_MESSAGE",
        ),
        aar = oppoAar,
    ),
    Vendor(
        "vivo", prop("vivo.appId") != null, """
        <meta-data android:name="com.vivo.push.app_id" android:value="${prop("vivo.appId")}" />
        <meta-data android:name="com.vivo.push.api_key" android:value="${prop("vivo.apiKey")}" />
        <receiver android:name=".vendor.VivoReceiver" android:exported="false">
            <intent-filter><action android:name="com.vivo.pushclient.action.RECEIVE" /></intent-filter>
        </receiver>""",
        repo = "https://repos.vivo.com.cn/maven/repository/external-lib/" to """vivo""",
        dependencies = listOf("vivo:vpush:4.1.7.0"),
    ),
).filter { it.enabled }

val generatedManifest = layout.buildDirectory.file("generated/pushplus/AndroidManifest.xml").get().asFile.apply {
    parentFile.mkdirs()
    writeText(
        buildString {
            appendLine("""<manifest xmlns:android="http://schemas.android.com/apk/res/android">""")
            (listOf("android.permission.POST_NOTIFICATIONS") +
                listOfNotNull("android.permission.USE_FULL_SCREEN_INTENT".takeIf { prop("fullScreenIntent") == "true" }) +
                vendors.flatMap { it.permissions }
            ).forEach { appendLine("""    <uses-permission android:name="$it" />""") }
            vendors.joinToString("") { it.queries }.takeIf { it.isNotEmpty() }?.let { appendLine("    <queries>$it</queries>") }
            appendLine("    <application>")
            appendLine("        <!-- 通知按钮（不拉起 App 的那种）的回调入口，flutter_local_notifications 要求宿主声明，这里代劳 -->")
            appendLine("""        <receiver android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" android:exported="false" />""")
            appendLine("""        <meta-data android:name="pushplus.channelId" android:value="pp:$channelId" />""")
            appendLine("""        <meta-data android:name="pushplus.channelName" android:value="pp:${prop("channelName") ?: "Push"}" />""")
            prop("icon")?.let { appendLine("""        <meta-data android:name="pushplus.iconRes" android:resource="@drawable/$it" />""") }
            vendors.forEach { appendLine(it.manifest) }
            appendLine("    </application>")
            appendLine("</manifest>")
        },
    )
}
logger.lifecycle("flutter_push_plus: channels = APNS(iOS) + ${vendors.map { it.name }.ifEmpty { listOf("none") }}")

// 宿主 app 解析传递依赖时也要能找到厂商仓库，这里一并注入，免得使用者手动加；只放行各家自己的 group，防依赖混淆
rootProject.allprojects {
    repositories {
        // 华为官方要求放在最后
        vendors.mapNotNull { it.takeIf { v -> v.name != "huawei" }?.repo }
            .plus(vendors.mapNotNull { it.takeIf { v -> v.name == "huawei" }?.repo })
            .forEach { (url, group) ->
                maven(url) { content { includeGroupByRegex(group) } }
            }
    }
}

android {
    namespace = "com.will.flutter_push_plus"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            vendors.forEach { java.srcDirs("src/vendors/${it.name}") }
            manifest.srcFile(generatedManifest)
        }
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
        vendors.filter { it.proguard }.forEach { consumerProguardFiles("proguard/${it.name}.pro") }
    }
}

// manifest 引用宿主的图标资源，库模块单独校验必然找不到；宿主打包时会校验
tasks.matching { it.name.startsWith("verify") && it.name.endsWith("Resources") }.configureEach { enabled = false }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    vendors.forEach { vendor ->
        vendor.dependencies.forEach { implementation(it) }
        vendor.aar?.let { compileOnly(files(it)) }
    }
}

// 库模块不能直接打包本地 aar，改由宿主 app 依赖，使用者只需把 aar 放进 app/libs/
rootProject.findProject(":app")?.let { app ->
    vendors.mapNotNull { it.aar }.forEach { app.dependencies.add("implementation", files(it)) }
}
