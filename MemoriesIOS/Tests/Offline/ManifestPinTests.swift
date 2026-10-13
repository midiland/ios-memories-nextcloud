import XCTest
@testable import Memories

final class ManifestPinTests: XCTestCase {
    private func dsse(_ version: Int) throws -> AssetManifest {
        try AssetManifest(raw: Fixtures.dsseDescribe(version: version))
    }

    func testEverythingIsAllowedBeforeTheFirstDSSEManifest() throws {
        XCTAssertTrue(ManifestPin.allows(try AssetManifest(raw: Fixtures.describe()), after: nil))
        XCTAssertTrue(ManifestPin.allows(try dsse(1), after: nil))
    }

    func testLegacyManifestDoesNotPin() throws {
        XCTAssertNil(ManifestPin.updated(nil, accepting: try AssetManifest(raw: Fixtures.describe())))
    }

    func testLegacyManifestIsRefusedAfterDSSE() throws {
        let pin = ManifestPin.updated(nil, accepting: try dsse(100))
        XCTAssertEqual(pin, ManifestPin(targetsVersion: 100))
        XCTAssertFalse(ManifestPin.allows(try AssetManifest(raw: Fixtures.describe()), after: pin))
    }

    func testOlderTargetsAreRefused() throws {
        let pin = ManifestPin(targetsVersion: 100)
        XCTAssertFalse(ManifestPin.allows(try dsse(99), after: pin))
        XCTAssertTrue(ManifestPin.allows(try dsse(100), after: pin))
        XCTAssertTrue(ManifestPin.allows(try dsse(101), after: pin))
    }

    func testPinOnlyMovesForward() throws {
        let pin = ManifestPin(targetsVersion: 100)
        XCTAssertEqual(ManifestPin.updated(pin, accepting: try dsse(150)), ManifestPin(targetsVersion: 150))
        XCTAssertEqual(ManifestPin.updated(pin, accepting: try AssetManifest(raw: Fixtures.describe())), pin)
    }

    func testStoreIsPerAccountAndCleared() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ManifestPinTests"))
        defaults.removePersistentDomain(forName: "ManifestPinTests")
        let store = ManifestPinStore(defaults: defaults)
        let bob = Credentials(server: Fixtures.server, loginName: "bob", appPassword: "x")

        store.save(ManifestPin(targetsVersion: 7), for: Fixtures.credentials)
        XCTAssertEqual(store.pin(for: Fixtures.credentials), ManifestPin(targetsVersion: 7))
        XCTAssertNil(store.pin(for: bob))

        store.removeAll()
        XCTAssertNil(store.pin(for: Fixtures.credentials))
        defaults.removePersistentDomain(forName: "ManifestPinTests")
    }
}
