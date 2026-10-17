package com.will.flutter_push_plus

import com.google.firebase.messaging.FirebaseMessagingService

/** 令牌轮换（重装、清数据、FCM 主动刷新）时把新令牌交给 Dart 重新注册。 */
class PushPlusMessagingService : FirebaseMessagingService() {
  override fun onNewToken(token: String) {
    FlutterPushPlusPlugin.postToken(token)
  }
}
