import XCTest
@testable import Memories

final class NativeXArgumentsTests: XCTestCase {
    func testTypedAccess() {
        let args = NativeXArguments(["#fff", true, NSNull(), 3])
        XCTAssertEqual(args.string(0), "#fff")
        XCTAssertTrue(args.bool(1))
        XCTAssertNil(args.string(2), "JS null")
        XCTAssertNil(args.string(3), "wrong type")
        XCTAssertFalse(args.bool(0), "wrong type")
    }

    func testOutOfRangeDefaults() {
        let args = NativeXArguments([])
        XCTAssertNil(args.string(5))
        XCTAssertFalse(args.bool(5))
    }

    func testMethodNamesMatchTheFrontend() {
        XCTAssertEqual(NativeXMethod(rawValue: "setThemeColor"), .setThemeColor)
        XCTAssertEqual(NativeXMethod(rawValue: "playVideo2"), .playVideo2)
        XCTAssertNil(NativeXMethod(rawValue: "unknown"))
    }
}
