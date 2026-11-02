# flutter_push_plus：厂商类靠反射和 manifest 引用；各厂商规则在 proguard/ 下，启用才加载
-keep class com.will.flutter_push_plus.** { *; }
