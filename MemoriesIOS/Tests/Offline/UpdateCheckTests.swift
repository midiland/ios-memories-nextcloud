import XCTest
@testable import Memories

@MainActor
final class UpdateCheckTests: XCTestCase {
    func testUnverifiableWebFilesAreReported() {
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: AppError.noSignedManifest), .unverifiable)
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: OfflineError.noManifest), .unverifiable)
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: OfflineError.integrity("memories-main.js")), .unverifiable)
    }

    func testTransientFailuresAreSilent() {
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: URLError(.notConnectedToInternet)), .upToDate)
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: OfflineError.download("memories-main.js", 503)), .upToDate)
        XCTAssertEqual(OfflineAppLoader.updateCheck(after: AppError.unexpectedStatus(500)), .upToDate)
    }
}
