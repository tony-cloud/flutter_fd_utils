import Flutter
import UIKit
import XCTest


@testable import flutter_fd_utils

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  func testGetFdReport() {
    let plugin = FlutterFdUtilsPlugin()

    let call = FlutterMethodCall(methodName: "getFdReport", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      let text = result as? String
      XCTAssertNotNil(text)
      XCTAssertTrue((text ?? "").isEmpty == false)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
