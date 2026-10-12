import XCTest
@testable import Memories

final class AppErrorTests: XCTestCase {
    func testSnapshotErrorsKeepTheirMeaning() {
        XCTAssertEqual(AppError.from(OfflineError.noManifest), .noSignedManifest)
        XCTAssertEqual(AppError.from(OfflineError.integrity("memories-main.js")), .webFilesCorrupted)
        XCTAssertEqual(AppError.from(OfflineError.download("memories-main.js", 404)), .unexpectedStatus(404))
        XCTAssertEqual(AppError.from(OfflineError.download("bad href", 0)), .invalidResponse)
    }

    func testAppErrorsPassThrough() {
        XCTAssertEqual(AppError.from(AppError.noSignedManifest), .noSignedManifest)
        XCTAssertEqual(AppError.from(AppError.localServerUnavailable), .localServerUnavailable)
    }

    func testOtherErrorsAreTransportErrors() {
        guard case .serverUnreachable = AppError.from(URLError(.notConnectedToInternet)) else {
            return XCTFail("A URLSession error must read as an unreachable server")
        }
    }
}
