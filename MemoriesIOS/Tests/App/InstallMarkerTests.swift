import XCTest
@testable import Memories

final class InstallMarkerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "fr.midiland.memories.tests.marker.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func run(existingData: Bool, purged: inout Int) -> Bool {
        var count = 0
        let result = InstallMarker(defaults: defaults).purgeKeychainIfReinstalled(
            hasExistingAppData: { existingData }, purge: { count += 1 }
        )
        purged += count
        return result
    }

    func testFreshInstallPurgesTheKeychainOnce() {
        var purged = 0
        XCTAssertTrue(run(existingData: false, purged: &purged))
        XCTAssertFalse(run(existingData: false, purged: &purged), "only on the first launch")
        XCTAssertEqual(purged, 1)
    }

    func testUpdateOfAnExistingInstallKeepsTheSession() {
        var purged = 0
        XCTAssertFalse(run(existingData: true, purged: &purged))
        XCTAssertEqual(purged, 0)
        XCTAssertFalse(run(existingData: false, purged: &purged), "the marker is set after the first launch")
        XCTAssertEqual(purged, 0)
    }

    func testPurgeDeletesTheKeychainItems() throws {
        let credentials = CredentialStore(service: "fr.midiland.memories.tests.\(UUID().uuidString)")
        let pending = PendingWipeStore(service: "fr.midiland.memories.tests.\(UUID().uuidString)")
        try credentials.save(Fixtures.credentials)
        try pending.save(Fixtures.credentials)
        InstallMarker(defaults: defaults).purgeKeychainIfReinstalled(
            hasExistingAppData: { false }, purge: { credentials.delete(); pending.delete() }
        )
        XCTAssertNil(credentials.load())
        XCTAssertNil(pending.load())
    }

    func testDataWiperKeepsTheMarkerSoALaterLoginSurvivesRelaunch() async throws {
        InstallMarker(defaults: defaults).purgeKeychainIfReinstalled(hasExistingAppData: { false }, purge: {})
        defaults.set("x", forKey: "other")
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let wiper = DataWiper(
            appSupport: folder, caches: folder, temporary: folder, defaults: defaults, defaultsDomain: suite,
            credentialStore: CredentialStore(service: "fr.midiland.memories.tests.\(UUID().uuidString)")
        )
        await wiper.run()
        XCTAssertNil(defaults.object(forKey: "other"))
        XCTAssertTrue(defaults.bool(forKey: InstallMarker.key))
        var purged = 0
        XCTAssertFalse(run(existingData: false, purged: &purged))
        XCTAssertEqual(purged, 0, "credentials saved after the wipe must survive the next launch")
    }
}
