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

    // MARK: - Progress callback (issue #14)

    func testExtractReportsProgressForEachFile() throws {
        let zip = try fixture("zipstreamer-album")
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        var doneValues: [Int] = []
        var totalValues: [Int] = []
        let files = try ZipExtractor.extract(zip, into: folder) { done, total in
            doneValues.append(done)
            totalValues.append(total)
        }

        // 3 files in the fixture, progress reported after each one.
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(doneValues, [1, 2, 3])
        XCTAssertEqual(totalValues, [3, 3, 3])
    }

    func testExtractProgressCountsOnlyFileEntries() throws {
        // mixed-entries has 3 file entries (a.jpg, a.jpg duplicate, evil.mov).
        let zip = try fixture("mixed-entries")
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        var lastTotal = 0
        _ = try ZipExtractor.extract(zip, into: folder) { _, total in
            lastTotal = total
        }

        XCTAssertEqual(lastTotal, 3)
    }

    func testExtractWithoutProgressCallback() throws {
        let zip = try fixture("zipstreamer-album")
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // No callback: should not crash.
        let files = try ZipExtractor.extract(zip, into: folder)
        XCTAssertEqual(files.count, 3)
    }

    // MARK: - Robustness (disk full, zip bomb, cancellation)

    /// Minimal ZIP of stored entries; `declared` is the uncompressed size written in the
    /// directory (it can lie about the real content to simulate a bomb).
    private func makeStoredZip(_ entries: [(name: String, content: Data, declared: UInt32)]) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        var body = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let offset = UInt32(body.count)
            body += le(UInt32(0x0403_4B50)) + le(UInt16(20)) + le(UInt16(0x0800)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0))
            body += le(UInt32(0)) + le(UInt32(entry.content.count)) + le(entry.declared) + le(UInt16(name.count)) + le(UInt16(0)) + name
            body += entry.content
            directory += le(UInt32(0x0201_4B50)) + le(UInt16(20)) + le(UInt16(20)) + le(UInt16(0x0800)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0))
            directory += le(UInt32(0)) + le(UInt32(entry.content.count)) + le(entry.declared)
            directory += le(UInt16(name.count)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt32(0)) + le(offset) + name
        }
        var end = le(UInt32(0x0605_4B50)) + le(UInt16(0)) + le(UInt16(0)) + le(UInt16(entries.count)) + le(UInt16(entries.count))
        end += le(UInt32(directory.count)) + le(UInt32(body.count)) + le(UInt16(0))
        return body + directory + end
    }

    private func write(_ data: Data) throws -> URL {
        let url = try Fixtures.temporaryDirectory().appendingPathComponent("test.zip")
        try data.write(to: url)
        return url
    }

    private func contents(of folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func testHandMadeZipExtracts() throws {
        let zip = try write(makeStoredZip([("a.jpg", Data("hello".utf8), 5)]))
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }
        let files = try ZipExtractor.extract(zip, into: folder)
        XCTAssertEqual(try Data(contentsOf: files[0]), Data("hello".utf8))
    }

    func testEntryLargerThanDeclaredIsRejectedAndRemoved() throws {
        // Declares 10 bytes but holds 1000: must stop at the declared size, not fill the disk.
        let zip = try write(makeStoredZip([
            ("ok.jpg", Data("fine".utf8), 4),
            ("bomb.jpg", Data(repeating: 0x41, count: 1000), 10),
        ]))
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }
        XCTAssertThrowsError(try ZipExtractor.extract(zip, into: folder)) { error in
            guard case ZipArchive.ZipError.sizeExceeded = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(contents(of: folder), [], "partial and earlier files are removed")
    }

    func testNotEnoughFreeSpaceFailsBeforeWritingAnything() throws {
        let zip = try fixture("zipstreamer-album") // 3 × 18,304 bytes
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertThrowsError(try ZipExtractor.extract(zip, into: folder, availableCapacity: { _ in 50_000 })) { error in
            guard case ZipArchive.ZipError.insufficientSpace = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(contents(of: folder), [])
        XCTAssertEqual(try ZipExtractor.extract(zip, into: folder, availableCapacity: { _ in 60_000 }).count, 3)
        XCTAssertEqual(try ZipExtractor.extract(zip, into: try Fixtures.temporaryDirectory(), availableCapacity: { _ in nil }).count, 3)
    }

    func testCancellationStopsTheExtraction() async throws {
        let zip = try fixture("zipstreamer-album")
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let task = Task { () throws -> [URL] in
            while !Task.isCancelled { await Task.yield() }
            return try ZipExtractor.extract(zip, into: folder)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("must be cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(contents(of: folder), [])
    }
}
