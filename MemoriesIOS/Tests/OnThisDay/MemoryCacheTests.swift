import XCTest
@testable import Memories

final class MemoryCacheTests: XCTestCase {
    private var root: URL!
    private var cache: MemoryCache!

    override func setUpWithError() throws {
        root = try Fixtures.temporaryDirectory()
        cache = MemoryCache(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(_ id: Int64, years: Int = 1) -> MemoryEntry {
        MemoryEntry(fileid: id, dayid: 100, yearsAgo: years, imageName: MemoryCache.imageName(fileid: id))
    }

    func testEmptyCacheHasNothing() {
        XCTAssertTrue(cache.entries(forDay: 5).isEmpty)
        XCTAssertFalse(cache.hasDay(5))
    }

    func testStoreAndReadBack() throws {
        try cache.store(days: [5: [entry(1), entry(2, years: 2)]], images: ["1.jpg": Data([1]), "2.jpg": Data([2])])
        XCTAssertEqual(cache.entries(forDay: 5).map(\.fileid), [1, 2])
        XCTAssertEqual(cache.entries(forDay: 5)[1].yearsAgo, 2)
        XCTAssertEqual(try Data(contentsOf: cache.imageURL(for: entry(2))), Data([2]))
    }

    func testEmptyDayCountsAsPrepared() throws {
        try cache.store(days: [5: []], images: [:])
        XCTAssertTrue(cache.hasDay(5))
        XCTAssertTrue(cache.entries(forDay: 5).isEmpty)
    }

    func testStoreReplacesAPreparedDayAndKeepsOthers() throws {
        try cache.store(days: [5: [entry(1)], 6: [entry(2)]], images: [:])
        try cache.store(days: [5: [entry(3)]], images: [:])
        XCTAssertEqual(cache.entries(forDay: 5).map(\.fileid), [3])
        XCTAssertEqual(cache.entries(forDay: 6).map(\.fileid), [2])
    }

    func testPruneDropsPastDaysAndOrphanImages() throws {
        try cache.store(
            days: [4: [entry(1)], 5: [entry(2)], 6: [entry(3)]],
            images: ["1.jpg": Data([1]), "2.jpg": Data([2]), "3.jpg": Data([3])])
        cache.prune(before: 5)

        XCTAssertFalse(cache.hasDay(4))
        XCTAssertTrue(cache.hasDay(5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.imageURL(for: entry(1)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.imageURL(for: entry(2)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.imageURL(for: entry(3)).path))
    }

    func testPruneKeepsAnImageSharedByAKeptDay() throws {
        try cache.store(days: [4: [entry(1)], 6: [entry(1)]], images: ["1.jpg": Data([1])])
        cache.prune(before: 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.imageURL(for: entry(1)).path))
    }

    func testRemoveAllErasesEverything() throws {
        try cache.store(days: [5: [entry(1)]], images: ["1.jpg": Data([1])])
        cache.removeAll()
        XCTAssertFalse(cache.hasDay(5))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.imageURL(for: entry(1)).path))
    }

    func testCorruptIndexReadsAsEmpty() throws {
        try cache.store(days: [5: [entry(1)]], images: [:])
        try Data("not json".utf8).write(to: root.appendingPathComponent("onthisday/index.json"))
        XCTAssertFalse(cache.hasDay(5))
    }

    func testUnknownIndexVersionReadsAsEmpty() throws {
        try cache.store(days: [5: [entry(1)]], images: [:])
        try Data(#"{"version":2,"days":{"5":[]}}"#.utf8).write(to: root.appendingPathComponent("onthisday/index.json"))
        XCTAssertFalse(cache.hasDay(5))
    }

    // MARK: - Cursor

    func testCursorStartsAtZero() {
        XCTAssertEqual(cache.cursor(forDay: 5), 0)
    }

    func testAdvanceCursorCounts() {
        cache.advanceCursor(forDay: 5)
        cache.advanceCursor(forDay: 5)
        XCTAssertEqual(cache.cursor(forDay: 5), 2)
    }

    func testCursorRestartsOnANewDay() {
        cache.advanceCursor(forDay: 5)
        XCTAssertEqual(cache.cursor(forDay: 6), 0)
        cache.advanceCursor(forDay: 6)
        XCTAssertEqual(cache.cursor(forDay: 6), 1)
        XCTAssertEqual(cache.cursor(forDay: 5), 0)
    }

    func testCursorSurvivesStoringMemories() throws {
        cache.advanceCursor(forDay: 5)
        try cache.store(days: [5: [entry(1)]], images: ["1.jpg": Data([1])])
        XCTAssertEqual(cache.cursor(forDay: 5), 1)
    }

    func testRemoveAllResetsTheCursor() {
        cache.advanceCursor(forDay: 5)
        cache.removeAll()
        XCTAssertEqual(cache.cursor(forDay: 5), 0)
    }

    func testCorruptCursorReadsAsZero() throws {
        cache.advanceCursor(forDay: 5)
        try Data("nope".utf8).write(to: root.appendingPathComponent("onthisday/cursor.json"))
        XCTAssertEqual(cache.cursor(forDay: 5), 0)
    }
}
