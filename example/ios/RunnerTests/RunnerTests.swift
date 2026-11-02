import XCTest

@testable import flutter_push_plus

class RunnerTests: XCTestCase {
  private func provision(_ entitlements: String) -> Data {
    var data = Data([0x30, 0x82, 0xff, 0x00])
    data.append(
      Data(
        """
        <?xml version="1.0"?><plist version="1.0"><dict><key>Entitlements</key><dict>\(entitlements)</dict></dict></plist>
        """.utf8))
    data.append(Data([0xff, 0x00]))
    return data
  }

  func testApsEnvironment() {
    let aps = "<key>aps-environment</key>"
    XCTAssertEqual(
      FlutterPushPlusPlugin.apsEnvironment(provision: provision("\(aps)<string>development</string>")), "sandbox")
    XCTAssertEqual(
      FlutterPushPlusPlugin.apsEnvironment(provision: provision("\(aps)<string>production</string>")), "production")
    XCTAssertNil(FlutterPushPlusPlugin.apsEnvironment(provision: provision("")))
    XCTAssertNil(FlutterPushPlusPlugin.apsEnvironment(provision: nil))
    XCTAssertNil(FlutterPushPlusPlugin.apsEnvironment(provision: Data("</plist> junk <?xml x".utf8)))
  }
}
