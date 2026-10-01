import XCTest
@testable import Memories

final class LocalFolderTests: XCTestCase {
    private let available = [
        LocalFolder(id: LocalFolder.libraryId, name: "All photos", enabled: true),
        LocalFolder(id: "album-1", name: "Trip", enabled: false),
        LocalFolder(id: "album-2", name: "Family", enabled: false),
    ]

    func testDefaultsEnableTheWholeLibraryOnly() {
        let merged = LocalFolder.merge(available: available, saved: [])
        XCTAssertEqual(merged.map(\.enabled), [true, false, false])
    }

    func testSavedChoicesWinAndRemovedAlbumsDisappear() {
        let saved = [
            LocalFolder(id: LocalFolder.libraryId, name: "x", enabled: false),
            LocalFolder(id: "album-2", name: "x", enabled: true),
            LocalFolder(id: "deleted-album", name: "x", enabled: true),
        ]
        let merged = LocalFolder.merge(available: available, saved: saved)
        XCTAssertEqual(merged.map(\.id), [LocalFolder.libraryId, "album-1", "album-2"])
        XCTAssertEqual(merged.map(\.enabled), [false, false, true])
        XCTAssertEqual(merged[2].name, "Family", "names come from the library")
    }

    func testJSONMatchesTheFrontendConfig() throws {
        let json = #"[{"id":"library","name":"All photos","enabled":true}]"#
        let folders = try JSONDecoder().decode([LocalFolder].self, from: Data(json.utf8))
        XCTAssertEqual(folders, [LocalFolder(id: "library", name: "All photos", enabled: true)])
    }
}
