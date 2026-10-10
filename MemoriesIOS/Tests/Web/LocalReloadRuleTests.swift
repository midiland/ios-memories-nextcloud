import XCTest
@testable import Memories

final class LocalReloadRuleTests: XCTestCase {
    private let page = URL(string: "http://127.0.0.1:62079/nextcloud/index.php/apps/memories/thisday")!

    private func onActive(
        page: URL?, port: UInt16 = 62079, terminated: Bool = false, unreachable: Bool = false
    ) -> LocalReloadRule.Action {
        LocalReloadRule.onBecomeActive(
            page: page, serverPort: port, contentProcessTerminated: terminated, showsUnreachableError: unreachable
        )
    }

    private func connectionError(_ code: Int, url: String) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: url)!])
    }

    func testNothingToDoWhenPageIsAlive() {
        XCTAssertEqual(onActive(page: page), .none)
        XCTAssertEqual(onActive(page: nil), .none)
    }

    func testReloadsAfterContentProcessTermination() {
        XCTAssertEqual(onActive(page: page, terminated: true), .reload)
        XCTAssertEqual(onActive(page: nil, terminated: true), .loadEntry)
    }

    func testLoadsEntryWhenPortChanged() {
        XCTAssertEqual(onActive(page: page, port: 50000), .loadEntry)
        XCTAssertEqual(onActive(page: page, port: 50000, terminated: true), .loadEntry)
    }

    func testRestartsFromUnreachableScreen() {
        XCTAssertEqual(onActive(page: page, unreachable: true), .restart)
        XCTAssertEqual(onActive(page: nil, terminated: true, unreachable: true), .restart)
    }

    func testRetriesLocalConnectionErrorsOnce() {
        for code in [NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut] {
            let error = connectionError(code, url: page.absoluteString)
            XCTAssertTrue(LocalReloadRule.shouldRetry(error, alreadyRetried: false), "\(code)")
            XCTAssertFalse(LocalReloadRule.shouldRetry(error, alreadyRetried: true), "\(code)")
        }
    }

    func testDoesNotRetryRemoteOrOtherErrors() {
        let remote = connectionError(NSURLErrorCannotConnectToHost, url: "https://cloud.example.com/")
        XCTAssertFalse(LocalReloadRule.shouldRetry(remote, alreadyRetried: false))
        let offline = connectionError(NSURLErrorNotConnectedToInternet, url: page.absoluteString)
        XCTAssertFalse(LocalReloadRule.shouldRetry(offline, alreadyRetried: false))
        let other = NSError(domain: "WebKitErrorDomain", code: 101)
        XCTAssertFalse(LocalReloadRule.shouldRetry(other, alreadyRetried: false))
    }
}
