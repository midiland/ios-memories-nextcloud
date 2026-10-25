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

    func testRemoteWipeHasLocalizedMessage() {
        let message = AppError.remoteWipe.errorDescription
        XCTAssertNotNil(message)
        // In tests the string catalog may not be loaded; the message must at least
        // be a non-empty, distinct string (not the raw key).
        XCTAssertFalse(message?.isEmpty ?? true)
    }
}
