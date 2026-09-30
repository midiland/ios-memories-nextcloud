import XCTest
@testable import Memories

final class SemanticVersionTests: XCTestCase {
    private func v(_ text: String) -> SemanticVersion { SemanticVersion(text) }

    func testNumericComparison() {
        XCTAssertLessThan(v("9.0.0"), v("9.0.1"))
        XCTAssertLessThan(v("9.9.9"), v("10.0.0"))
        XCTAssertLessThan(v("9.2"), v("9.10"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(v("9.1") < v("9.1.0"))
        XCTAssertFalse(v("9.1.0") < v("9.1"))
    }

    func testPreReleaseIsLowerThanRelease() {
        XCTAssertLessThan(v("9.0.0-rc.1"), v("9.0.0"))
        XCTAssertFalse(v("9.0.0") < v("9.0.0-rc.1"))
    }

    func testPreReleasesCompareNumerically() {
        XCTAssertLessThan(v("9.0.0-rc.2"), v("9.0.0-rc.10"))
        XCTAssertLessThan(v("9.0.0-alpha.1"), v("9.0.0-rc.1"))
    }

    func testMinimumServerVersion() {
        let minimum = v(AppConstants.minServerVersion)
        XCTAssertFalse(v("9.0.0-rc.1") < minimum)
        XCTAssertFalse(v("9.1.0-alpha.2") < minimum)
        XCTAssertLessThan(v("8.9.9"), minimum)
        XCTAssertLessThan(v("9.0.0-beta.3"), minimum)
    }
}
