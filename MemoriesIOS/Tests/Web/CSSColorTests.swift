import UIKit
import XCTest
@testable import Memories

final class CSSColorTests: XCTestCase {
    /// RGBA components rounded to 0…255.
    private func rgba(_ css: String) -> [Int]? {
        guard let color = UIColor(css: css) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Int(($0 * 255).rounded()) }
    }

    func testHexFormats() {
        XCTAssertEqual(rgba("#fff"), [255, 255, 255, 255])
        XCTAssertEqual(rgba("#112233"), [17, 34, 51, 255])
        XCTAssertEqual(rgba(" #11223380 "), [17, 34, 51, 128])
        XCTAssertEqual(rgba("#ABCDEF"), [171, 205, 239, 255])
    }

    func testRGBFormats() {
        XCTAssertEqual(rgba("rgb(1, 2, 3)"), [1, 2, 3, 255])
        XCTAssertEqual(rgba("rgba(0,0,0,0.5)"), [0, 0, 0, 128])
        XCTAssertEqual(rgba("rgb(10 20 30 / 0.2)"), [10, 20, 30, 51])
    }

    func testUnknownFormats() {
        XCTAssertNil(rgba("red"))
        XCTAssertNil(rgba("#12"))
        XCTAssertNil(rgba("#zzzzzz"))
        XCTAssertNil(rgba("rgb(1, 2)"))
    }
}
