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

/** 宿主 android/gradle.properties 里的 pushPlus.* 配置；没填的厂商整个不编进包。 */
fun prop(key: String) = (findProperty("pushPlus.$key") as String?)?.trim()?.takeIf { it.isNotEmpty() }

/** 小米、OPPO 官方只给 aar，由宿主放进 android/app/libs/。 */
fun hostAar(prefix: String) = rootProject.file("app/libs").listFiles()
    ?.firstOrNull { it.name.startsWith(prefix) && it.name.endsWith(".aar") }

val xiaomiAar = hostAar("MiPush_SDK_Client")
val oppoAar = hostAar("com.heytap.msp")

data class Vendor(val name: String, val enabled: Boolean, val manifest: String = "", val queries: String = "")

/** 自家 meta-data 统一加前缀，防止纯数字的 ID 被当成整数解析丢精度。 */
fun meta(key: String) = """<meta-data android:name="pushplus.$key" android:value="pp:${prop(key)}" />"""

val vendors = listOf(
    Vendor(
        "fcm", prop("fcm.appId") != null || rootProject.file("app/google-services.json").exists(),
        listOf("fcm.apiKey", "fcm.appId", "fcm.projectId", "fcm.senderId").filter { prop(it) != null }
            .joinToString("") { meta(it) } + """
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="${prop("channelId") ?: "push"}" />${prop("icon")?.let { """
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/$it" />""" } ?: ""}
        <service android:name=".vendor.FcmService" android:exported="false">
            <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter>
        </service>""",
    ),
    Vendor(
        "huawei", prop("huawei.appId") != null, """
        ${meta("huawei.appId")}
        <meta-data android:name="com.huawei.hms.client.appid" android:value="appid=${prop("huawei.appId")}" />
        <service android:name=".vendor.HuaweiService" android:exported="false">
            <intent-filter><action android:name="com.huawei.push.action.MESSAGING_EVENT" /></intent-filter>
        </service>""",
    ),
    Vendor(
        "honor", prop("honor.appId") != null, """
        <meta-data android:name="com.hihonor.push.app_id" android:value="${prop("honor.appId")}" />
        <service android:name=".vendor.HonorService" android:exported="false">
            <intent-filter><action android:name="com.hihonor.push.action.MESSAGING_EVENT" /></intent-filter>
        </service>""",
        """<intent><action android:name="com.hihonor.push.action.BIND_PUSH_SERVICE" /></intent>""",
    ),
    Vendor(
        "xiaomi", prop("xiaomi.appId") != null && xiaomiAar != null, """
        ${meta("xiaomi.appId")}${meta("xiaomi.appKey")}
        <receiver android:name=".vendor.XiaomiReceiver" android:exported="true">
            <intent-filter>
                <action android:name="com.xiaomi.mipush.RECEIVE_MESSAGE" />
                <action android:name="com.xiaomi.mipush.MESSAGE_ARRIVED" />
                <action android:name="com.xiaomi.mipush.ERROR" />
            </intent-filter>
        </receiver>""",
    ),
    Vendor(
        "oppo", prop("oppo.appKey") != null && oppoAar != null, """
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
    ),
    Vendor(
        "vivo", prop("vivo.appId") != null, """
        <meta-data android:name="com.vivo.push.app_id" android:value="${prop("vivo.appId")}" />
        <meta-data android:name="com.vivo.push.api_key" android:value="${prop("vivo.apiKey")}" />
        <receiver android:name=".vendor.VivoReceiver" android:exported="false">
            <intent-filter><action android:name="com.vivo.pushclient.action.RECEIVE" /></intent-filter>
        </receiver>""",
    ),
).filter { it.enabled }

val generatedManifest = layout.buildDirectory.file("generated/pushplus/AndroidManifest.xml").get().asFile.apply {
    parentFile.mkdirs()
    writeText(
        """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
${if (prop("fullScreenIntent") == "true") "    <uses-permission android:name=\"android.permission.USE_FULL_SCREEN_INTENT\" />\n" else ""}${vendors.joinToString("") { it.queries }.takeIf { it.isNotEmpty() }?.let { "    <queries>$it</queries>\n" } ?: ""}    <application>
        <!-- 通知按钮（不拉起 App 的那种）的回调入口，flutter_local_notifications 要求宿主声明，这里代劳 -->
        <receiver android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" android:exported="false" />
        ${listOf("channelId", "channelName", "icon").filter { prop(it) != null }.joinToString("") { meta(it) }}${vendors.joinToString("") { it.manifest }}
    </application>
</manifest>
""",
    )
}
logger.lifecycle("flutter_push_plus: channels = APNS(iOS) + ${vendors.map { it.name }.ifEmpty { listOf("none") }}")

// 宿主 app 解析传递依赖时也要能找到厂商仓库，这里一并注入，免得使用者手动加
rootProject.allprojects {
  repositories {
    vendors.forEach {
        when (it.name) {
            "honor" -> maven("https://developer.honor.com/repo")
            "vivo" -> maven("https://repos.vivo.com.cn/maven/repository/external-lib/")
        }
    }
    // 华为官方要求放在最后
    if (vendors.any { it.name == "huawei" }) maven("https://developer.huawei.com/repo/")
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
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    vendors.forEach {
        when (it.name) {
            "fcm" -> implementation("com.google.firebase:firebase-messaging:24.1.0")
            "huawei" -> implementation("com.huawei.hms:push:6.13.0.301")
            "honor" -> implementation("com.hihonor.mcs:push:10.0.39.302")
            "vivo" -> implementation("vivo:vpush:4.1.7.0")
            "xiaomi" -> compileOnly(files(xiaomiAar!!))
            "oppo" -> compileOnly(files(oppoAar!!))
        }
    }
}

// 库模块不能直接打包本地 aar，改由宿主 app 依赖，使用者只需把 aar 放进 app/libs/
rootProject.findProject(":app")?.let { app ->
    listOfNotNull(xiaomiAar.takeIf { vendors.any { it.name == "xiaomi" } }, oppoAar.takeIf { vendors.any { it.name == "oppo" } })
        .forEach { app.dependencies.add("implementation", files(it)) }
}
