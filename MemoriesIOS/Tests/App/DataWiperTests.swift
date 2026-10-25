import XCTest
@testable import Memories

/// Tests for `DataWiper` (issue #15): the local purge that runs on a remote wipe.
/// Uses injected temporary directories so the real app data is never touched.
final class DataWiperTests: XCTestCase {
    private var appSupport: URL!
    private var caches: URL!
    private var temporary: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var credentialStore: CredentialStore!
    private var wiper: DataWiper!

    override func setUp() async throws {
        try await super.setUp()
        appSupport = try Fixtures.temporaryDirectory()
        caches = try Fixtures.temporaryDirectory()
        temporary = try Fixtures.temporaryDirectory()
        // A suite-isolated UserDefaults so the real defaults are never touched.
        suiteName = "fr.midiland.memories.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        // A dedicated Keychain service so the real credentials are never touched.
        credentialStore = CredentialStore(service: "fr.midiland.memories.tests.wiper.\(UUID().uuidString)")
        wiper = DataWiper(
            appSupport: appSupport,
            caches: caches,
            temporary: temporary,
            defaults: defaults,
            defaultsDomain: suiteName,
            credentialStore: credentialStore
        )
    }

    override func tearDown() async throws {
        credentialStore.delete()
        try? FileManager.default.removeItem(at: appSupport)
        try? FileManager.default.removeItem(at: caches)
        try? FileManager.default.removeItem(at: temporary)
        defaults.removePersistentDomain(forName: suiteName)
        wiper = nil
        try await super.tearDown()
    }

    // MARK: - Snapshots

    func testRemovesOfflineSnapshots() async throws {
        let offline = appSupport.appendingPathComponent("offline", isDirectory: true)
        let serverDir = offline.appendingPathComponent("https_cloud.example.com", isDirectory: true)
        let snapshot = serverDir.appendingPathComponent("abc123", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot.appendingPathComponent("js"), withIntermediateDirectories: true)
        try Data().write(to: snapshot.appendingPathComponent(".ready"))

        await wiper.run()

        XCTAssertFalse(FileManager.default.fileExists(atPath: offline.path))
    }

    func testKeepsOtherAppSupportDirectories() async throws {
        let keep = appSupport.appendingPathComponent("keep-me", isDirectory: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        try Data().write(to: keep.appendingPathComponent("file.txt"))

        await wiper.run()

        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    // MARK: - RemoteCopyStore

    func testRemovesRemoteCopies() async throws {
        let photos = appSupport.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data().write(to: photos.appendingPathComponent("alice@cloud.example.com.json"))

        await wiper.run()

        XCTAssertFalse(FileManager.default.fileExists(atPath: photos.path))
    }

    // MARK: - Temporary and caches

    func testRemovesTemporaryFiles() async throws {
        let file = temporary.appendingPathComponent("download.bin")
        try Data().write(to: file)

        await wiper.run()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRemovesCacheFiles() async throws {
        let file = caches.appendingPathComponent("cache.db")
        try Data().write(to: file)

        await wiper.run()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - UserDefaults

    func testRemovesAllUserDefaultsKeys() async {
        // The whole domain is cleared: any key, known prefix or not.
        defaults.set(true, forKey: "photos.enabled")
        defaults.set("data", forKey: "nativex.localFolders")
        defaults.set(Data(), forKey: "manifestPin.alice@https://cloud.example.com")
        defaults.set("cloud.example.com", forKey: "lastServerInput")
        defaults.set("future.value", forKey: "unknownPrefix")

        await wiper.run()

        XCTAssertNil(defaults.object(forKey: "photos.enabled"))
        XCTAssertNil(defaults.object(forKey: "nativex.localFolders"))
        XCTAssertNil(defaults.object(forKey: "manifestPin.alice@https://cloud.example.com"))
        XCTAssertNil(defaults.object(forKey: "lastServerInput"))
        XCTAssertNil(defaults.object(forKey: "unknownPrefix"), "unknown-prefix keys must also be erased")
    }

    func testOnlyClearsItsOwnDefaultsDomain() async {
        let other = UserDefaults(suiteName: suiteName + ".other")!
        other.set("keep", forKey: "some.key")
        defer { other.removePersistentDomain(forName: suiteName + ".other") }

        await wiper.run()

        XCTAssertEqual(other.string(forKey: "some.key"), "keep", "another domain must be left alone")
    }

    // MARK: - Credentials

    func testRemovesCredentialsFromKeychain() async throws {
        try credentialStore.save(Fixtures.credentials)
        XCTAssertNotNil(credentialStore.load())

        await wiper.run()

        XCTAssertNil(credentialStore.load(), "credentials must be erased from the Keychain")
    }

    // MARK: - Idempotence

    func testRunIsIdempotent() async {
        // Two runs must not crash (every step is best-effort).
        await wiper.run()
        await wiper.run()
    }

    func testRunOnEmptyDirectories() async {
        // No data at all: must not crash.
        await wiper.run()
    }
}
