import XCTest
@testable import Memories

final class DownloadURLPolicyTests: XCTestCase {
    private let origin = URL(string: "https://cloud.example.com")!
    private let local = LocalServerAccess(port: 62079, secret: "s")

    private func allowed(_ text: String, local: LocalServerAccess? = nil) -> Bool {
        DownloadURLPolicy.isAllowed(URL(string: text)!, serverOrigin: origin, local: local)
    }

    func testAllowsTheAccountServer() {
        XCTAssertTrue(allowed("https://cloud.example.com/nextcloud/index.php/apps/memories/api/download"))
        XCTAssertTrue(allowed("https://CLOUD.example.com:443/x"))
    }

    func testAllowsTheLocalServerOnItsPortOnly() {
        XCTAssertTrue(allowed("http://127.0.0.1:62079/api/x", local: local))
        XCTAssertFalse(allowed("http://127.0.0.1:9999/api/x", local: local))
        XCTAssertFalse(allowed("http://127.0.0.1:62079/api/x")) // server not running
    }

    func testRejectsOtherSchemesAndHosts() {
        for text in [
            "file:///var/mobile/Containers/secret.json", "data:text/plain,hi", "ftp://cloud.example.com/x",
            "http://cloud.example.com/x", // downgrade
            "https://evil.example.org/x", "https://cloud.example.com.evil.org/x",
            "https://cloud.example.com:8443/x", "https://user:pw@cloud.example.com/x",
        ] {
            XCTAssertFalse(allowed(text, local: local), text)
        }
    }

    func testDownloaderRefusesBeforeAnyRequest() async {
        let downloader = AuthenticatedDownloader(credentials: Fixtures.credentials)
        do {
            _ = try await downloader.download(URL(string: "file:///etc/hosts")!)
            XCTFail("must throw")
        } catch {
            guard case AppError.invalidURL = error else { return XCTFail("\(error)") }
        }
    }
}
