import XCTest
@testable import Memories

/// Expected values computed independently (Python `hashlib` / `zoneinfo`) with the server formulas.
final class PhotoIDsTests: XCTestCase {
    private let paris = TimeZone(identifier: "Europe/Paris")!

    func testAuidMatchesServerFormula() {
        // md5("1700000000" + "12345")
        XCTAssertEqual(PhotoIDs.auid(epoch: 1_700_000_000, size: 12_345), "9715f9b5eb4fe45ea2e8996f113a24c4")
    }

    func testBuidMatchesServerFormula() {
        // md5("IMG_0001.HEIC" + "size=12345")
        XCTAssertEqual(PhotoIDs.buid(basename: "IMG_0001.HEIC", size: 12_345), "43a8997e3db0ceb078f43b8dfdbcd457")
    }

    func testEpochDropsSubseconds() {
        XCTAssertEqual(PhotoIDs.epoch(Date(timeIntervalSince1970: 1_790_807_400.987)), 1_790_807_400)
        XCTAssertEqual(PhotoIDs.epoch(Date(timeIntervalSince1970: -0.5)), -1)
    }

    func testDayIdUsesTheCaptureWallClockDate() {
        // 2026-10-01 00:30 in Paris = 2026-09-30 22:30 UTC: the server's day is October 1st.
        let date = Date(timeIntervalSince1970: 1_790_807_400)
        XCTAssertEqual(PhotoIDs.wallClockEpoch(date, in: paris), 1_790_814_600)
        XCTAssertEqual(PhotoIDs.dayId(date, in: paris), 20_727)
        XCTAssertEqual(PhotoIDs.dayId(date, in: TimeZone(identifier: "UTC")!), 20_726)
    }

    func testDayIdBeforeEpochRoundsDown() {
        XCTAssertEqual(PhotoIDs.dayId(Date(timeIntervalSince1970: -3_600), in: TimeZone(identifier: "UTC")!), -1)
    }

    func testFileIdIsStableUniqueAndJSSafe() {
        let a = PhotoIDs.fileId(localIdentifier: "8C1A7E2B-0000-4000-8000-000000000001/L0/001")
        let b = PhotoIDs.fileId(localIdentifier: "8C1A7E2B-0000-4000-8000-000000000002/L0/001")
        XCTAssertEqual(a, PhotoIDs.fileId(localIdentifier: "8C1A7E2B-0000-4000-8000-000000000001/L0/001"))
        XCTAssertNotEqual(a, b)
        for id in [a, b] {
            XCTAssertGreaterThanOrEqual(id, 1 << 52)
            XCTAssertLessThan(id, 1 << 53, "must stay an exact JS number")
        }
    }
}
