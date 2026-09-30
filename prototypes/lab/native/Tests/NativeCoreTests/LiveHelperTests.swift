import Foundation
import XCTest
@testable import NativeCore

// Opt-in integration: REAL parent helper, real isolated tmux shell, real read-only git.
// Never launches GUI or dispatches application actions.
final class LiveHelperTests: XCTestCase {
    func testRealTerminalAndGit() async throws {
        guard let config = ProcessInfo.processInfo.environment["TETHR_NATIVE_LIVE_CONFIG"] else {
            throw XCTSkip("Set TETHR_NATIVE_LIVE_CONFIG to run real helper integration")
        }
        let helper = try Helper(config: config)
        let catalog = try Wire.catalog(await helper.call(["catalog"]))
        for action in ["terminal.step", "command.git-status"] {
            XCTAssertTrue(catalog.contains { $0.id == action })
            let request = UUID().uuidString
            let data = try await helper.call(["dispatch", action, "--request-id", request])
            let display = try Wire.result(data, request: request, action: action)
            XCTAssertFalse(display.isEmpty)
            let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let result = try XCTUnwrap(response["data"] as? [String: Any])
            if action == "terminal.step" {
                XCTAssertGreaterThan(try XCTUnwrap(result["counter"] as? Int), 0)
                XCTAssertGreaterThan(try XCTUnwrap(result["shellPID"] as? Int), 0)
                XCTAssertFalse(try XCTUnwrap(result["shellNonce"] as? String).isEmpty)
                XCTAssertFalse(try XCTUnwrap(result["cwd"] as? String).isEmpty)
            } else {
                XCTAssertEqual(try XCTUnwrap(result["exitCode"] as? Int), 0)
                XCTAssertNotNil(result["stdout"] as? String)
            }
            print("REAL_HELPER_RECEIPT " + String(decoding: data, as: UTF8.self))
        }
    }
}
