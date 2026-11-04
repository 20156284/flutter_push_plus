import AVFoundation
import CallKit
import CryptoKit
import Flutter
import PushKit

/// iOS 系统来电：自己持有 PushKit 与 CallKit，宿主只需在 Info.plist 的 UIBackgroundModes 加 voip。
final class PushPlusVoip: NSObject, PKPushRegistryDelegate, CXProviderDelegate {
  private static let declinedKey = "flutter_push_plus.voip.declined"
  private static let declinedTtl: TimeInterval = 90
  private static let ringTimeout: TimeInterval = 60
  private static let closedCapacity = 32
  /// 须常驻持有，否则收不到 VoIP 推送。
  private static var shared: PushPlusVoip?

  private final class Call {
    let extra: [String: Any]
    let callerName: String
    let callerId: String
    let hasVideo: Bool
    var accepted = false
    var timeout: DispatchWorkItem?
    init(extra: [String: Any], callerName: String, callerId: String, hasVideo: Bool) {
      self.extra = extra
      self.callerName = callerName
      self.callerId = callerId
      self.hasVideo = hasVideo
    }

    /// 回给 Dart 的整通数据，与 Dart 侧 `PushVoipCall` 对应。
    func payload(_ uuid: UUID) -> [String: Any] {
      [
        "uuid": uuid.uuidString.lowercased(), "accepted": accepted, "callerName": callerName,
        "callerId": callerId, "hasVideo": hasVideo, "extra": extra,
      ]
    }
  }

  private let channel: FlutterMethodChannel
  private let provider: CXProvider
  private let callController = CXCallController()
  private let registry = PKPushRegistry(queue: .main)
  private var token: String?
  private var calls: [UUID: Call] = [:]
  /// Dart 已结束的通话；它的 PushKit 来电若迟到，上报后立刻结束。
  private var closedCalls = Set<UUID>()

  /// 主引擎注册时调用；Info.plist 没有 voip 时通道照常应答，但全部返回空结果。
  static func start(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "flutter_push_plus/voip", binaryMessenger: messenger)
    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    guard modes?.contains("voip") == true else {
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getToken": result(nil)
        case "reportIncoming", "end", "connected": result(false)
        case "activeCalls", "takeDeclined": result([])
        case "setMuted": result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
      return
    }
    shared = PushPlusVoip(channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = true
    configuration.maximumCallGroups = 2
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.includesCallsInRecents = false
    provider = CXProvider(configuration: configuration)
    super.init()
    provider.setDelegate(self, queue: .main)
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
  }

  // MARK: Dart → 原生

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getToken":
      result(token)
    case "reportIncoming":
      let callId = args["callId"] as? String ?? ""
      var extra = args["extra"] as? [String: Any] ?? [:]
      extra["callId"] = callId
      report(
        uuid: Self.callUuid(callId),
        call: Call(
          extra: extra, callerName: args["callerName"] as? String ?? "",
          callerId: args["callerId"] as? String ?? "", hasVideo: args["hasVideo"] as? Bool ?? false),
        cancel: false
      ) { result($0) }
    case "end":
      guard let uuid = (args["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return result(false) }
      closedCalls.insert(uuid)
      if closedCalls.count > Self.closedCapacity { closedCalls = [uuid] }
      guard calls[uuid] != nil || isLive(uuid) else { return result(false) }
      finish(uuid)
      provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      result(true)
    case "connected":
      guard let uuid = (args["uuid"] as? String).flatMap(UUID.init(uuidString:)),
        let cxCall = callController.callObserver.calls.first(where: { $0.uuid == uuid }),
        !cxCall.hasConnected, !cxCall.hasEnded
      else { return result(false) }
      callController.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { result($0 == nil) }
    case "setMuted":
      guard let uuid = (args["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return result(nil) }
      let action = CXSetMutedCallAction(call: uuid, muted: args["muted"] as? Bool ?? false)
      callController.request(CXTransaction(action: action)) { _ in result(nil) }
    case "activeCalls":
      result(calls.map { $0.value.payload($0.key) })
    case "takeDeclined":
      result(takeDeclined())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func isLive(_ uuid: UUID) -> Bool {
    callController.callObserver.calls.contains { $0.uuid == uuid && !$0.hasEnded }
  }

  /// 上报来电前先配好 playAndRecord；激活交给 CallKit，这里不 setActive。
  private func configureCallAudio() {
    try? AVAudioSession.sharedInstance().setCategory(
      .playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
  }

  private static func update(callerName: String?, callerId: String?, hasVideo: Bool) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerId ?? "")
    update.localizedCallerName = callerName ?? ""
    update.hasVideo = hasVideo
    update.supportsDTMF = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    return update
  }

  /// 上报一通来电。`cancel` 时（含 UUID 已存在报错）回调里立刻结束并发 cancel 事件，保证每条推送都先上报再收尾。
  private func report(
    uuid: UUID, call: Call, cancel: Bool, completion: @escaping (Bool) -> Void
  ) {
    configureCallAudio()
    let update = Self.update(callerName: call.callerName, callerId: call.callerId, hasVideo: call.hasVideo)
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      guard let self else { return completion(false) }
      if cancel {
        self.finish(uuid)
        self.provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
        self.emit(["type": "action", "action": "cancel", "uuid": uuid.uuidString.lowercased()])
        return completion(error == nil)
      }
      if let error = error as? NSError {
        // 同一通已在响（推送与 WS 几乎同时到）算上报成功，不覆盖记录、不重排超时
        let exists = error.domain == CXErrorDomainIncomingCall
          && error.code == CXErrorCodeIncomingCallError.callUUIDAlreadyExists.rawValue
        return completion(exists)
      }
      self.calls[uuid] = call
      self.scheduleTimeout(uuid)
      completion(true)
    }
  }

  private func scheduleTimeout(_ uuid: UUID) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, let call = self.calls[uuid], !call.accepted else { return }
      self.calls[uuid] = nil
      self.provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
      self.emit(["type": "action", "action": "timeout", "uuid": uuid.uuidString.lowercased()])
    }
    calls[uuid]?.timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.ringTimeout, execute: work)
  }

  /// 移除记录并取消振铃计时。
  private func finish(_ uuid: UUID) {
    calls.removeValue(forKey: uuid)?.timeout?.cancel()
  }

  private func emit(_ event: [String: Any]) {
    channel.invokeMethod("event", arguments: event)
  }

  // MARK: 拒绝落盘

  /// 连同整通数据落盘；UserDefaults 不收 NSNull，extra 先转成 JSON 字符串。
  private func saveDeclined(_ uuid: UUID, _ call: Call) {
    let defaults = UserDefaults.standard
    var saved = defaults.dictionary(forKey: Self.declinedKey) as? [String: [String: Any]] ?? [:]
    let extra = (try? JSONSerialization.data(withJSONObject: call.extra)).flatMap {
      String(data: $0, encoding: .utf8)
    }
    saved[uuid.uuidString.lowercased()] = [
      "at": Date().timeIntervalSince1970, "callerName": call.callerName, "callerId": call.callerId,
      "hasVideo": call.hasVideo, "extra": extra ?? "{}",
    ]
    defaults.set(saved, forKey: Self.declinedKey)
  }

  /// 取走并清空落盘记录，只返回未过期的。
  private func takeDeclined() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    let saved = defaults.dictionary(forKey: Self.declinedKey) as? [String: [String: Any]] ?? [:]
    defaults.removeObject(forKey: Self.declinedKey)
    let now = Date().timeIntervalSince1970
    return saved.compactMap { uuid, item in
      guard now - (item["at"] as? Double ?? 0) < Self.declinedTtl else { return nil }
      let extra = (item["extra"] as? String).flatMap { $0.data(using: .utf8) }
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      return [
        "uuid": uuid, "accepted": false, "callerName": item["callerName"] as? String ?? "",
        "callerId": item["callerId"] as? String ?? "", "hasVideo": item["hasVideo"] as? Bool ?? false,
        "extra": extra ?? [:],
      ]
    }
  }

  /// 与 Dart 侧 `PushVoip.uuidOf` 同算法：RFC 4122 v5（DNS 命名空间 + callId），小写。
  static func callUuid(_ callId: String) -> UUID {
    let namespace: [UInt8] = [
      0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
      0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
    ]
    var bytes = Array(Insecure.SHA1.hash(data: namespace + Array(callId.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  // MARK: PKPushRegistryDelegate

  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    token = hex
    channel.invokeMethod("token", arguments: hex)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    token = nil
    channel.invokeMethod("token", arguments: nil)
  }

  /// iOS 13+ 每条 VoIP 推送都必须同步上报 CallKit，否则进程被杀；INVITE、CANCEL 都走同一条上报路径。
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else { return completion() }
    let fields = payload.dictionaryPayload
    let callId = fields["callId"] as? String ?? ""
    let uuid = Self.callUuid(callId)
    let cancel = callId.isEmpty || fields["action"] as? String == "CANCEL" || closedCalls.contains(uuid)
    let reserved: Set<String> = ["hasVideo", "callerName", "callerId"]
    var extra = fields.reduce(into: [String: Any]()) { result, field in
      guard let key = field.key as? String, !reserved.contains(key),
        JSONSerialization.isValidJSONObject([field.value])
      else { return }
      result[key] = field.value
    }
    extra["callId"] = callId
    let call = Call(
      extra: extra, callerName: fields["callerName"] as? String ?? "",
      callerId: fields["callerId"] as? String ?? "", hasVideo: fields["hasVideo"] as? String == "1")
    report(uuid: uuid, call: call, cancel: cancel) { [weak self] reported in
      if reported && !cancel {
        self?.emit(["type": "incoming"].merging(call.payload(uuid)) { $1 })
      }
      completion()
    }
  }

  // MARK: CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    let ended = Array(calls.keys)
    ended.forEach(finish)
    ended.forEach { emit(["type": "action", "action": "end", "uuid": $0.uuidString.lowercased()]) }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let call = calls[action.callUUID] else { return action.fail() }
    call.accepted = true
    call.timeout?.cancel()
    emit(["type": "action", "action": "accept", "uuid": action.callUUID.uuidString.lowercased()])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    let uuid = action.callUUID
    let call = calls[uuid]
    let accepted = call?.accepted ?? false
    finish(uuid)
    if let call, !accepted { saveDeclined(uuid, call) }
    emit(["type": "action", "action": accepted ? "end" : "decline", "uuid": uuid.uuidString.lowercased()])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    emit(["type": "mute", "uuid": action.callUUID.uuidString.lowercased(), "muted": action.isMuted])
    action.fulfill()
  }

  func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
    action.fulfill()
    if !action.isOnHold { postInterruptionEnded() }
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    guard let action = action as? CXCallAction, calls[action.callUUID] != nil else { return }
    emit(["type": "action", "action": "timeout", "uuid": action.callUUID.uuidString.lowercased()])
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    configureCallAudio()
    postInterruptionEnded()
  }

  /// WebRTC 靠这条通知在 CallKit 激活会话后恢复音频采集。
  private func postInterruptionEnded() {
    NotificationCenter.default.post(
      name: AVAudioSession.interruptionNotification, object: self,
      userInfo: [
        AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
        AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
      ])
  }
}
