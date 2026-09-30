import XCTest
@testable import Memories

final class SnapshotStoreTests: XCTestCase {
    private var directory: URL!
    private let store = SnapshotStore()

    override func setUpWithError() throws {
        directory = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testServerDirectoryIsASafePathSegment() {
        let server = ServerURL(userInput: "http://nas.local:8080/nextcloud")!
        XCTAssertEqual(store.serverDirectory(for: server).lastPathComponent, "http_nas.local_8080")
        XCTAssertEqual(store.serverDirectory(for: Fixtures.server).lastPathComponent, "https_cloud.example.com")
    }

    func testSnapshotIsOnlyUsableOnceReady() throws {
        let manifest = try AssetManifest(raw: Fixtures.describe())
        let snapshotDirectory = directory.appendingPathComponent(manifest.key, isDirectory: true)
        try store.prepareEmptyDirectory(snapshotDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotDirectory.appendingPathComponent("js").path))
        XCTAssertNil(store.snapshot(at: snapshotDirectory))

        try store.markReady(snapshotDirectory, manifest: manifest)
        let snapshot = try XCTUnwrap(store.snapshot(at: snapshotDirectory))
        XCTAssertEqual(snapshot.key, manifest.key)
        XCTAssertEqual(snapshot.manifest.js.count, manifest.js.count)
        XCTAssertEqual(snapshot.jsDirectory.lastPathComponent, "js")
        XCTAssertEqual(snapshot.cssDirectory.lastPathComponent, "css")
    }
}
