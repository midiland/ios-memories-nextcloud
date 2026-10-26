import XCTest
@testable import Memories

final class MemoryRefresherTests: XCTestCase {
    private final class FakeFetcher: OnThisDayFetching {
        var photosByRequest: [[ServerPhoto]] = []
        var photoError: Error?
        var previewError: Error?
        private(set) var requestedDays: [[Int]] = []
        private(set) var previewed: [Int64] = []

        func photos(onDays dayIds: [Int], credentials: Credentials) async throws -> [ServerPhoto] {
            requestedDays.append(dayIds)
            if let photoError { throw photoError }
            return photosByRequest.isEmpty ? [] : photosByRequest.removeFirst()
        }

        func preview(fileid: Int64, size: Int, credentials: Credentials) async throws -> Data {
            previewed.append(fileid)
            if let previewError { throw previewError }
            return Data([UInt8(fileid & 0xFF)])
        }
    }

    private var root: URL!
    private var cache: MemoryCache!
    private var fetcher: FakeFetcher!
    private var refresher: MemoryRefresher!
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private lazy var now = utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
    private let today = 20_752

    override func setUpWithError() throws {
        root = try Fixtures.temporaryDirectory()
        cache = MemoryCache(root: root)
        fetcher = FakeFetcher()
        refresher = MemoryRefresher(fetcher: fetcher, cache: cache, calendar: utc)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func photo(_ id: Int64, dayid: Int) -> ServerPhoto {
        ServerPhoto(fileid: id, dayid: dayid, epoch: dayid * 86_400, w: 1, h: 1, size: 1,
                    basename: "\(id).jpg", buid: nil, isVideo: false)
    }

    func testRefreshPreparesTodayAndTheNextDays() async throws {
        let stored = try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(stored, MemoryRefresher.daysAhead)
        for offset in 0..<MemoryRefresher.daysAhead {
            XCTAssertTrue(cache.hasDay(today + offset), "day +\(offset)")
        }
        XCTAssertFalse(cache.hasDay(today + MemoryRefresher.daysAhead))
        XCTAssertEqual(fetcher.requestedDays.count, MemoryRefresher.daysAhead)
    }

    func testRefreshStoresEntriesAndThumbnails() async throws {
        fetcher.photosByRequest = [[photo(1, dayid: today - 365), photo(2, dayid: today - 730)]]
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)

        let entries = cache.entries(forDay: today)
        XCTAssertEqual(Set(entries.map(\.fileid)), [1, 2])
        XCTAssertEqual(Set(entries.map(\.yearsAgo)), [1, 2])
        for entry in entries {
            XCTAssertTrue(FileManager.default.fileExists(atPath: cache.imageURL(for: entry).path))
        }
    }

    func testRefreshQueriesTheDatesOfEachDisplayDay() async throws {
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        // Day +1 asks for 27 October of past years: its first id is 2025-10-27 - 3 days.
        XCTAssertEqual(fetcher.requestedDays[1][3], 20_388)
    }

    func testRefreshDoesNotDownloadAnAlreadyStoredThumbnailTwice() async throws {
        fetcher.photosByRequest = [[photo(1, dayid: today - 365)], [photo(1, dayid: today - 365)]]
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(fetcher.previewed.filter { $0 == 1 }.count, 1)
    }

    func testSecondRefreshOnlyRefetchesToday() async throws {
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        let before = fetcher.requestedDays.count
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(fetcher.requestedDays.count - before, 1)
    }

    func testRefreshAdvancesWithTheDateAndPrunesThePast() async throws {
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        let tomorrow = now.addingTimeInterval(86_400)
        try await refresher.refresh(credentials: Fixtures.credentials, now: tomorrow)
        XCTAssertFalse(cache.hasDay(today))
        XCTAssertTrue(cache.hasDay(today + MemoryRefresher.daysAhead))
    }

    func testFailedDayIsSkippedAndTheOthersAreStored() async throws {
        fetcher.photoError = AppError.unexpectedStatus(500)
        let stored = try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(stored, 0)
        XCTAssertFalse(cache.hasDay(today))
    }

    func testFailedThumbnailDropsOnlyThatEntry() async throws {
        fetcher.photosByRequest = [[photo(1, dayid: today - 365)]]
        fetcher.previewError = AppError.unexpectedStatus(404)
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertTrue(cache.hasDay(today))
        XCTAssertTrue(cache.entries(forDay: today).isEmpty)
    }

    func testAuthenticationFailureAbortsAndStoresNothing() async {
        fetcher.photoError = AppError.notAuthenticated
        do {
            try await refresher.refresh(credentials: Fixtures.credentials, now: now)
            XCTFail("Must throw")
        } catch AppError.notAuthenticated {
            XCTAssertFalse(cache.hasDay(today))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHiddenPhotosAreNotPickedAgain() async throws {
        cache.hide(fileid: 1)
        fetcher.photosByRequest = [[photo(1, dayid: today - 365), photo(2, dayid: today - 365)]]
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(cache.entries(forDay: today).map(\.fileid), [2])
        XCTAssertFalse(fetcher.previewed.contains(1), "A hidden photo must not be downloaded")
    }

    func testSameDayYieldsSamePicks() async throws {
        let photos = (1...30).map { photo(Int64($0), dayid: today - 365) }
        fetcher.photosByRequest = [photos]
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        let first = cache.entries(forDay: today).map(\.fileid)

        cache.removeAll()
        fetcher.photosByRequest = [photos]
        try await refresher.refresh(credentials: Fixtures.credentials, now: now)
        XCTAssertEqual(cache.entries(forDay: today).map(\.fileid), first)
    }
}
