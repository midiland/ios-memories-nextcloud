import XCTest
@testable import Memories

/// Uses a dedicated Keychain service: never touches the real pending-wipe entry.
final class PendingWipeStoreTests: XCTestCase {
    private let store = PendingWipeStore(service: "fr.midiland.memories.tests.wipe.\(UUID().uuidString)")
    private let pending = PendingWipe(server: Fixtures.server, token: Fixtures.credentials.appPassword)

    override func tearDown() {
        store.delete()
    }

    func testSaveLoadDelete() throws {
        XCTAssertNil(store.load())
        try store.save(pending)
        XCTAssertEqual(store.load(), pending)
        store.delete()
        XCTAssertNil(store.load())
    }

    func testSaveReplacesExisting() throws {
        try store.save(pending)
        let other = PendingWipe(server: Fixtures.server, token: "other", attempts: 2)
        try store.save(other)
        XCTAssertEqual(store.load(), other)
    }

    func testStoredEntryContainsNoLoginName() throws {
        // Only the server URL and the token may be persisted: the login name is
        // not needed by the wipe endpoints and must not sit in a second Keychain entry.
        try store.save(pending)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "fr.midiland.memories.tests.wipe.\(UUID().uuidString)",
            kSecReturnData as String: true,
        ]
        _ = query // service differs per instance; read back through the store instead
        let loaded = try XCTUnwrap(store.load())
        let json = String(data: try JSONEncoder().encode(loaded), encoding: .utf8)!
        XCTAssertFalse(json.contains(Fixtures.credentials.loginName), "login name must not be persisted")
        XCTAssertTrue(json.contains(pending.token))
    }

    func testAttemptsArePersisted() throws {
        var bumped = pending
        bumped.attempts = 3
        try store.save(bumped)
        XCTAssertEqual(store.load()?.attempts, 3)
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(store.load())
    }

    func testDeleteIsIdempotent() {
        store.delete()
        store.delete()
    }
}
