import XCTest
@testable import Memories

/// Uses a dedicated Keychain service: never touches the real pending-wipe entry.
final class PendingWipeStoreTests: XCTestCase {
    private let store = PendingWipeStore(service: "fr.midiland.memories.tests.wipe.\(UUID().uuidString)")

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

    func testSaveReplacesExisting() throws {
        try store.save(Fixtures.credentials)
        let other = Credentials(server: Fixtures.server, loginName: "bob", appPassword: "other")
        try store.save(other)
        XCTAssertEqual(store.load(), other)
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(store.load())
    }

    func testDeleteIsIdempotent() {
        store.delete()
        store.delete()
    }
}
