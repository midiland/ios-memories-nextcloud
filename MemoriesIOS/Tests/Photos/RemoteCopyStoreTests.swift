import XCTest
@testable import Memories

final class RemoteCopyStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testUpdateReplacesTheResultOfCheckedPhotos() {
        let store = RemoteCopyStore(credentials: Fixtures.credentials, directory: directory)
        store.update(checked: ["a", "b"], matched: ["a", "b"])
        store.update(checked: ["b", "c"], matched: ["c"])
        XCTAssertTrue(store.contains("a"), "not checked again")
        XCTAssertFalse(store.contains("b"), "no longer on the server")
        XCTAssertTrue(store.contains("c"))
    }

    func testPersistsPerAccount() {
        RemoteCopyStore(credentials: Fixtures.credentials, directory: directory).insert(["a"])
        XCTAssertTrue(RemoteCopyStore(credentials: Fixtures.credentials, directory: directory).contains("a"))

        let other = Credentials(server: Fixtures.server, loginName: "bob", appPassword: "x")
        XCTAssertFalse(RemoteCopyStore(credentials: other, directory: directory).contains("a"))
    }
}
