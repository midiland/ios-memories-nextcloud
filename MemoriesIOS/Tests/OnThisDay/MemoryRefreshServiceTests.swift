import XCTest
@testable import Memories

@MainActor
final class MemoryRefreshServiceTests: XCTestCase {
    private final class FakeFetcher: OnThisDayFetching {
        var error: Error?
        private(set) var photoCalls = 0

        func photos(onDays dayIds: [Int], credentials: Credentials) async throws -> [ServerPhoto] {
            photoCalls += 1
            if let error { throw error }
            return []
        }

        func preview(fileid: Int64, size: Int, credentials: Credentials) async throws -> Data { Data() }
    }

    private var root: URL!
    private var cache: MemoryCache!
    private var fetcher: FakeFetcher!
    private var clock: Date!
    private var widgetInstalled = true
    private var reloads = 0
    private var service: MemoryRefreshService!
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        root = try Fixtures.temporaryDirectory()
        cache = MemoryCache(root: root)
        fetcher = FakeFetcher()
        clock = utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
        widgetInstalled = true
        reloads = 0
        service = MemoryRefreshService(
            fetcher: fetcher, cache: cache, calendar: utc,
            now: { [unowned self] in clock },
            hasWidget: { [unowned self] in widgetInstalled },
            widgetsDidChange: { [unowned self] in reloads += 1 })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testRefreshFillsTheCacheAndReloadsTheWidget() async {
        let updated = await service.refresh(credentials: Fixtures.credentials)
        XCTAssertTrue(updated)
        XCTAssertTrue(service.isUpToDate())
        XCTAssertEqual(reloads, 1)
    }

    func testNothingIsDownloadedWithoutAWidget() async {
        widgetInstalled = false
        let updated = await service.refresh(credentials: Fixtures.credentials)
        XCTAssertFalse(updated)
        XCTAssertEqual(fetcher.photoCalls, 0)
    }

    func testRemovingTheWidgetClearsTheCache() async {
        await service.refresh(credentials: Fixtures.credentials)
        widgetInstalled = false
        await service.refresh(credentials: Fixtures.credentials)
        XCTAssertFalse(service.isUpToDate())
        XCTAssertFalse(cache.hasDay(OnThisDay.dayId(of: clock, calendar: utc)))
    }

    func testForegroundSkipsWhenTheCacheIsUpToDate() async {
        await service.refresh(credentials: Fixtures.credentials)
        let calls = fetcher.photoCalls
        clock = clock.addingTimeInterval(3600)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertEqual(fetcher.photoCalls, calls)
    }

    func testForegroundRefreshesWhenADayIsMissing() async {
        await service.refresh(credentials: Fixtures.credentials)
        let calls = fetcher.photoCalls
        // Next day: the horizon moved by one day, so one more day is missing.
        clock = clock.addingTimeInterval(86_400)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertGreaterThan(fetcher.photoCalls, calls)
        XCTAssertTrue(service.isUpToDate())
    }

    func testForegroundIsThrottledAfterAFailure() async {
        fetcher.error = AppError.unexpectedStatus(500)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        let calls = fetcher.photoCalls
        XCTAssertGreaterThan(calls, 0)

        clock = clock.addingTimeInterval(60)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertEqual(fetcher.photoCalls, calls, "Retried too soon")

        clock = clock.addingTimeInterval(MemoryRefreshService.minimumAttemptInterval)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertGreaterThan(fetcher.photoCalls, calls)
    }

    /// The reported bug: open the app (no widget yet), add the widget, come back to the app a
    /// minute later: the memories must load, not wait for the failure back-off.
    func testAddingTheWidgetThenReturningToTheAppLoadsTheMemories() async {
        widgetInstalled = false
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertEqual(fetcher.photoCalls, 0)

        widgetInstalled = true
        clock = clock.addingTimeInterval(60)
        await service.refreshIfNeeded(credentials: Fixtures.credentials)

        XCTAssertGreaterThan(fetcher.photoCalls, 0)
        XCTAssertTrue(service.isUpToDate())
        XCTAssertEqual(reloads, 1)
    }

    func testCheckingForAWidgetDoesNotStartTheBackOff() async {
        widgetInstalled = false
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        widgetInstalled = true
        await service.refreshIfNeeded(credentials: Fixtures.credentials)
        XCTAssertGreaterThan(fetcher.photoCalls, 0, "No attempt was made without a widget")
    }

    func testRevokedCredentialsClearTheCacheAndReload() async {
        await service.refresh(credentials: Fixtures.credentials)
        fetcher.error = AppError.notAuthenticated
        clock = clock.addingTimeInterval(86_400)
        let updated = await service.refresh(credentials: Fixtures.credentials)
        XCTAssertFalse(updated)
        XCTAssertFalse(cache.hasDay(OnThisDay.dayId(of: clock, calendar: utc)))
        XCTAssertEqual(reloads, 2)
    }

    func testIsNotUpToDateWhenEmpty() {
        XCTAssertFalse(service.isUpToDate())
    }
}
