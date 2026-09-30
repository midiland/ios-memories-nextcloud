import XCTest
@testable import Memories

/// Uses a dedicated Keychain service: never touches the real account's credentials.
final class CredentialStoreTests: XCTestCase {
    private let store = CredentialStore(service: "gallery.memories.ios.tests.\(UUID().uuidString)")

    override func tearDown() {
        store.delete()
    }

    func testSaveLoadDelete() throws {
        XCTAssertNil(store.load())
        try store.save(Fixtures.credentials)
        XCTAssertEqual(store.load(), Fixtures.credentials)
        store.delete()
        XCTAssertNil(store.load())
    }

    func testSaveReplacesExistingCredentials() throws {
        try store.save(Fixtures.credentials)
        let other = Credentials(server: Fixtures.server, loginName: "bob", appPassword: "other")
        try store.save(other)
        XCTAssertEqual(store.load(), other)
    }
}
