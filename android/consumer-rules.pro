# flutter_push_plus：各厂商官方混淆规则，未启用的厂商不影响
-keep class com.will.flutter_push_plus.** { *; }
-keepattributes *Annotation*,Exceptions,InnerClasses,Signature,SourceFile,LineNumberTable
# 华为
-dontwarn com.huawei.**
-keep class com.huawei.hianalytics.** { *; }
-keep class com.huawei.updatesdk.** { *; }
-keep class com.huawei.hms.** { *; }
# 荣耀
-dontwarn com.hihonor.**
-keep class com.hihonor.push.** { *; }
# 小米
-dontwarn com.xiaomi.**
# OPPO
-dontwarn com.heytap.**
-keep class com.heytap.msp.** { *; }
-keep class com.heytap.mcssdk.** { *; }
-keep class com.mcs.aidl.** { *; }
# vivo
-dontwarn com.vivo.push.**
-keep class com.vivo.push.** { *; }
-keep class com.vivo.vms.** { *; }
