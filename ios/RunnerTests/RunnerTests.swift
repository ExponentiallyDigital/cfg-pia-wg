import Flutter
import UIKit
import XCTest

@testable import Runner

/// ID-404: the iOS clipboard, through the same handler the channel calls. Run on a simulator by the
/// ios-build job in .github/workflows/quality_and_security.yml.
class RunnerTests: XCTestCase {

  private let secret = "cfg-pia-wg RunnerTests secret"

  /// Calls the handler as the channel would, and returns its reply.
  private func call(_ method: String, _ arguments: Any? = nil) -> Any? {
    var reply: Any?
    let answered = expectation(description: method)
    SensitiveClipboard.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value in
      reply = value
      answered.fulfill()
    }
    wait(for: [answered], timeout: 5)
    return reply
  }

  override func tearDown() {
    UIPasteboard.general.items = []
    super.tearDown()
  }

  func testCopyThenClearLeavesNothing() {
    _ = call(SensitiveClipboard.copySensitive, ["text": secret, "expiresInSeconds": 60])
    XCTAssertEqual(UIPasteboard.general.string, secret, "the copy didn't reach the clipboard")

    XCTAssertEqual(call(SensitiveClipboard.clearClipboard) as? Bool, true, "the clear didn't report an empty clipboard")
    XCTAssertFalse(UIPasteboard.general.hasStrings)
    XCTAssertNil(UIPasteboard.general.string)
  }

  /// The copy carries an expiry, so iOS removes it even when the app isn't running to clear it.
  func testCopyExpiresOnItsOwn() {
    _ = call(SensitiveClipboard.copySensitive, ["text": secret, "expiresInSeconds": 2])
    XCTAssertTrue(UIPasteboard.general.hasStrings)

    let deadline = Date().addingTimeInterval(6)
    while UIPasteboard.general.hasStrings && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    XCTAssertFalse(UIPasteboard.general.hasStrings, "still on the clipboard after its expiry")
  }

  func testAnUnknownMethodIsNotImplemented() {
    XCTAssertTrue((call("noSuchMethod") as? NSObject) === FlutterMethodNotImplemented)
  }
}
