import XCTest
@testable import Memories

final class ZipExtractorTests: XCTestCase {
    func testSafeNameKeepsOnlyTheBaseName() {
        XCTAssertEqual(ZipExtractor.safeName("Holidays/IMG_0001.HEIC"), "IMG_0001.HEIC")
        XCTAssertEqual(ZipExtractor.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(ZipExtractor.safeName("a\\\\b\\\\photo.jpg"), "photo.jpg")
    }

    func testSafeNameSkipsMetadataAndEmptyNames() {
        for path in ["__MACOSX/._IMG.jpg", ".DS_Store", "folder/", "..", "  "] {
            XCTAssertNil(ZipExtractor.safeName(path), path)
        }
    }

    func testUniqueNameAddsASuffixCaseInsensitively() {
        var taken = Set<String>()
        XCTAssertEqual(ZipExtractor.uniqueName("IMG.jpg", taken: &taken), "IMG.jpg")
        XCTAssertEqual(ZipExtractor.uniqueName("img.JPG", taken: &taken), "img (2).JPG")
        XCTAssertEqual(ZipExtractor.uniqueName("IMG.jpg", taken: &taken), "IMG (3).jpg")
        XCTAssertEqual(ZipExtractor.uniqueName("README", taken: &taken), "README")
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "zip"))
    }

    private func extract(_ zip: URL) throws -> (files: [URL], folder: URL) {
        let folder = try Fixtures.temporaryDirectory()
        return (try ZipExtractor.extract(zip, into: folder), folder)
    }

    func testReadsTheZip64ArchivesOfTheServer() throws {
        // Downloaded from Memories (`api/download/{handle}`): ZipStreamer, ZIP64 fields, data descriptors.
        let zip = try fixture("zipstreamer-album")
        XCTAssertTrue(ZipExtractor.isZip(zip))
        let (files, folder) = try extract(zip)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(files.map(\.lastPathComponent), ["IMG_1001.JPG", "IMG_1002.JPG", "IMG_1003.JPG"])
        for file in files {
            let data = try Data(contentsOf: file)
            XCTAssertEqual(data.count, 18_304)
            XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]), "a JPEG")
        }
    }

    func testExtractsDeflatedAndStoredEntriesFlat() throws {
        let (files, folder) = try extract(try fixture("mixed-entries"))
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(files.map(\.lastPathComponent), ["a.jpg", "a (2).jpg", "evil.mov"])
        XCTAssertEqual(try Data(contentsOf: files[0]), Data(String(repeating: "one", count: 1000).utf8))
        XCTAssertEqual(try Data(contentsOf: files[1]), Data("two".utf8))
        XCTAssertTrue(files.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL })
    }

    func testPlainFilesAreNotZips() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.zip")
        try Data("not a zip".utf8).write(to: file)
        XCTAssertFalse(ZipExtractor.isZip(file))
    }
}
