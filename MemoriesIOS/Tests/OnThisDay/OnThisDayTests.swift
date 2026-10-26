import XCTest
@testable import Memories

final class OnThisDayTests: XCTestCase {
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
    }

    private func photo(_ id: Int64, dayid: Int, name: String = "p.jpg", video: Bool = false) -> ServerPhoto {
        ServerPhoto(fileid: id, dayid: dayid, epoch: dayid * 86_400, w: 100, h: 100, size: 1,
                    basename: name, buid: nil, isVideo: video)
    }

    // MARK: - dayId

    func testDayIdOfKnownDate() {
        XCTAssertEqual(OnThisDay.dayId(of: date(2026, 10, 26), calendar: utc), 20_752)
    }

    func testDayIdUsesLocalCalendarDay() {
        // 23:30 in New York is already the next day in UTC: the local day must win.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let evening = newYork.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 30))!
        XCTAssertEqual(OnThisDay.dayId(of: evening, calendar: newYork), 20_752)
    }

    func testMemoryDayMatchesOnThisDay() {
        let now = date(2026, 10, 26)
        XCTAssertEqual(MemoryDay.id(of: now, calendar: utc), OnThisDay.dayId(of: now, calendar: utc))
    }

    // MARK: - dayIds

    func testDayIdsCountAndOrder() {
        let ids = OnThisDay.dayIds(for: date(2026, 10, 26), maxYears: 2, range: 3, calendar: utc)
        XCTAssertEqual(ids.count, 14)
        // First year back: 2025-10-26 ± 3 days.
        XCTAssertEqual(Array(ids[0..<7]), Array(20_384...20_390))
        XCTAssertEqual(ids[3], 20_387)
    }

    func testDayIdsZeroRange() {
        let ids = OnThisDay.dayIds(for: date(2026, 10, 26), maxYears: 1, range: 0, calendar: utc)
        XCTAssertEqual(ids, [20_387])
    }

    func testDayIdsLeapDayRollsOverToMarchFirst() {
        // 2024-02-29, one year back = 2023-02-29, which does not exist: the frontend gets 1 March.
        let ids = OnThisDay.dayIds(for: date(2024, 2, 29), maxYears: 1, range: 0, calendar: utc)
        XCTAssertEqual(ids, [19_417])
    }

    func testDayIdsInvalidArguments() {
        XCTAssertTrue(OnThisDay.dayIds(for: Date(), maxYears: 0, calendar: utc).isEmpty)
        XCTAssertTrue(OnThisDay.dayIds(for: Date(), range: -1, calendar: utc).isEmpty)
    }

    // MARK: - displayable

    func testDisplayableDropsVideosAndHiddenFiles() {
        let kept = photo(1, dayid: 100)
        let photos = [kept, photo(2, dayid: 100, video: true), photo(3, dayid: 100, name: ".hidden.jpg")]
        XCTAssertEqual(OnThisDay.displayable(photos), [kept])
    }

    // MARK: - groupByYear

    func testGroupByYearSplitsOnGapOverThirtyDays() {
        let today = 20_752
        let photos = [
            photo(1, dayid: today - 365), photo(2, dayid: today - 363),
            photo(3, dayid: today - 730), photo(4, dayid: today - 731),
        ]
        let years = OnThisDay.groupByYear(photos, todayDayId: today)
        XCTAssertEqual(years.map(\.yearsAgo), [1, 2])
        XCTAssertEqual(years[0].photos.map(\.fileid), [2, 1])
        XCTAssertEqual(years[1].photos.map(\.fileid), [3, 4])
    }

    func testGroupByYearKeepsYearBoundaryTogether() {
        // 30 December and 2 January belong to the same anniversary of a 1 January date.
        let today = 20_453 // 2025-12-31
        let photos = [photo(1, dayid: today - 365 - 1), photo(2, dayid: today - 365 + 2)]
        let years = OnThisDay.groupByYear(photos, todayDayId: today)
        XCTAssertEqual(years.count, 1)
        XCTAssertEqual(years[0].photos.count, 2)
    }

    func testGroupByYearEmptyAndFiltered() {
        XCTAssertTrue(OnThisDay.groupByYear([], todayDayId: 20_752).isEmpty)
        XCTAssertTrue(OnThisDay.groupByYear([photo(1, dayid: 20_387, video: true)], todayDayId: 20_752).isEmpty)
    }

    func testYearsAgoIsAtLeastOne() {
        let years = OnThisDay.groupByYear([photo(1, dayid: 20_750)], todayDayId: 20_752)
        XCTAssertEqual(years.first?.yearsAgo, 1)
    }

    // MARK: - pick

    private func years(_ counts: [Int]) -> [OnThisDay.Year] {
        var id: Int64 = 0
        return counts.enumerated().map { index, count in
            OnThisDay.Year(yearsAgo: index + 1, photos: (0..<count).map { _ in
                id += 1
                return photo(id, dayid: 1000 + Int(id))
            })
        }
    }

    func testPickRespectsPerYearAndTotal() {
        let picked = OnThisDay.pick(from: years([10, 10, 10]), perYear: 2, maxTotal: 5, seed: 1)
        XCTAssertEqual(picked.count, 5)
        for yearsAgo in 1...3 {
            XCTAssertLessThanOrEqual(picked.filter { $0.yearsAgo == yearsAgo }.count, 2)
        }
    }

    func testPickSpreadsAcrossYearsMostRecentFirst() {
        let picked = OnThisDay.pick(from: years([5, 5, 5]), perYear: 3, maxTotal: 3, seed: 1)
        XCTAssertEqual(picked.map(\.yearsAgo), [1, 2, 3])
    }

    func testPickIsDeterministicForASeed() {
        let input = years([8, 8])
        let a = OnThisDay.pick(from: input, seed: 20_752).map(\.photo.fileid)
        let b = OnThisDay.pick(from: input, seed: 20_752).map(\.photo.fileid)
        XCTAssertEqual(a, b)
    }

    func testPickDiffersAcrossSeeds() {
        let input = years([30])
        let seeds = (1...10).map { OnThisDay.pick(from: input, perYear: 3, seed: $0).map(\.photo.fileid) }
        XCTAssertGreaterThan(Set(seeds).count, 1)
    }

    func testPickHandlesFewPhotosAndInvalidLimits() {
        XCTAssertEqual(OnThisDay.pick(from: years([1, 0, 2]), perYear: 3, seed: 1).count, 3)
        XCTAssertTrue(OnThisDay.pick(from: years([3]), perYear: 0, seed: 1).isEmpty)
        XCTAssertTrue(OnThisDay.pick(from: [], seed: 1).isEmpty)
    }

    func testPickNeverDuplicatesAPhoto() {
        let picked = OnThisDay.pick(from: years([4, 4]), perYear: 4, maxTotal: 20, seed: 7)
        XCTAssertEqual(Set(picked.map(\.photo.fileid)).count, picked.count)
    }

    func testSeededGeneratorIsStable() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }
}
