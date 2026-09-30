import XCTest
@testable import NativeCore
final class CoreTests: XCTestCase {
    func testFilterOrderAndTokens() {
        var m = Selection(); m.items = [Item(id: "1", title: "Git 状況", keywords: "Changes"), Item(id: "2", title: "Git", subtitle: "changes")]
        m.query = " CHANGES\n git "; XCTAssertEqual(m.filtered.map(\.id), ["1", "2"])
        m.query = "変更"; XCTAssertTrue(m.filtered.isEmpty); XCTAssertNil(m.begin())
    }
    func testBusyCompositionAndNavigation() {
        var m = Selection(); m.items = [Item(id: "1", title: "一"), Item(id: "2", title: "二")]
        XCTAssertNil(m.begin(composing: true)); XCTAssertFalse(m.busy)
        m.move(100); XCTAssertEqual(m.begin()?.id, "2"); XCTAssertNil(m.begin())
        m.finish(); m.move(-100); XCTAssertEqual(m.begin()?.id, "1")
    }
    func testWirePresentationAndMismatch() throws {
        let ok = Data(#"{"protocolVersion":1,"status":"ok","requestID":"r","actionID":"a","message":"完了","data":{"counter":2}}"#.utf8)
        let text = try Wire.result(ok, request: "r", action: "a")
        XCTAssertTrue(text.contains("完了")); XCTAssertTrue(text.contains("counter"))
        XCTAssertThrowsError(try Wire.result(ok, request: "other", action: "a"))
        let error = Data(#"{"protocolVersion":1,"status":"error","requestID":"r","actionID":"a","message":"失敗","errorCode":"gone"}"#.utf8)
        XCTAssertThrowsError(try Wire.result(error, request: "r", action: "a")) { XCTAssertTrue($0.localizedDescription.contains("gone: 失敗")) }
        XCTAssertThrowsError(try Wire.catalog(Data("not-json".utf8)))
    }
}
