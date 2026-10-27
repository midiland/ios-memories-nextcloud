import XCTest
@testable import Memories

final class MemoryTimelineTests: XCTestCase {
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute))!
    }

    private func entries(_ count: Int) -> [MemoryEntry] {
        (0..<count).map {
            MemoryEntry(fileid: Int64($0), dayid: 1, yearsAgo: $0 + 1, imageName: "\($0).jpg")
        }
    }

    private func schedule(_ count: Int, at now: Date) -> MemoryTimeline.Schedule {
        MemoryTimeline.schedule(entries: entries(count), now: now, calendar: utc)
    }

    func testEmptyScheduleRetriesLater() {
        let result = schedule(0, at: date(hour: 10))
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.reloadAt, date(hour: 13))
    }

    func testEmptyScheduleNeverRetriesPastMidnight() {
        let result = schedule(0, at: date(hour: 23))
        XCTAssertEqual(result.reloadAt, date(hour: 0).addingTimeInterval(86_400))
    }

    func testFirstItemStartsNow() {
        let now = date(hour: 10, minute: 10)
        XCTAssertEqual(schedule(3, at: now).items.first?.date, now)
    }

    func testSlotsAreHalfAnHourApart() {
        let items = schedule(3, at: date(hour: 10, minute: 10)).items
        XCTAssertEqual(items[1].date, date(hour: 10, minute: 30))
        XCTAssertEqual(items[2].date, date(hour: 11))
    }

    func testMemoryDependsOnTheSlotNotOnTheBuildTime() {
        // Slot 20 (10:00-10:30) shows entry 20 % 3 = 2, whether built at 10:00 or 10:25.
        XCTAssertEqual(schedule(3, at: date(hour: 10)).items[0].memory.fileid, 2)
        XCTAssertEqual(schedule(3, at: date(hour: 10, minute: 25)).items[0].memory.fileid, 2)
    }

    func testMemoriesCycleThroughTheEntries() {
        let ids = schedule(3, at: date(hour: 10)).items.prefix(4).map(\.memory.fileid)
        XCTAssertEqual(ids, [2, 0, 1, 2])
    }

    func testUpcomingAreTheFollowingMemories() {
        let items = schedule(5, at: date(hour: 10)).items
        // Slot 20 shows entry 0 (20 % 5), then 1 and 2.
        XCTAssertEqual(items[0].memory.fileid, 0)
        XCTAssertEqual(items[0].upcoming.map(\.fileid), [1, 2])
        XCTAssertEqual(items[1].upcoming.map(\.fileid), [2, 3])
    }

    func testUpcomingNeverRepeatsThePhotoShown() {
        for count in 1...4 {
            for item in schedule(count, at: date(hour: 10)).items {
                let shown = [item.memory] + item.upcoming
                XCTAssertEqual(Set(shown.map(\.fileid)).count, shown.count, "\(count) memories")
            }
        }
    }

    func testFewMemoriesGiveFewerUpcoming() {
        XCTAssertEqual(schedule(1, at: date(hour: 10)).items[0].upcoming.count, 0)
        XCTAssertEqual(schedule(2, at: date(hour: 10)).items[0].upcoming.count, 1)
        XCTAssertEqual(schedule(3, at: date(hour: 10)).items[0].upcoming.count, 2)
    }

    func testOffsetSkipsMemories() {
        let now = date(hour: 10)
        let skipped = MemoryTimeline.schedule(entries: entries(5), now: now, offset: 2, calendar: utc)
        XCTAssertEqual(skipped.items[0].memory.fileid, 2)
        XCTAssertEqual(skipped.items[0].upcoming.map(\.fileid), [3, 4])
    }

    func testOffsetWrapsAround() {
        let result = MemoryTimeline.schedule(entries: entries(3), now: date(hour: 10), offset: 7, calendar: utc)
        XCTAssertEqual(result.items[0].memory.fileid, (20 + 7) % 3)
    }

    func testSingleMemoryIgnoresTheOffset() {
        let result = MemoryTimeline.schedule(entries: entries(1), now: date(hour: 10), offset: 4, calendar: utc)
        XCTAssertEqual(result.items[0].memory.fileid, 0)
    }

    func testBuildsAtMostMaxSlotsAndReloadsAtTheirEnd() {
        let result = schedule(5, at: date(hour: 8))
        XCTAssertEqual(result.items.count, MemoryTimeline.maxSlots)
        XCTAssertEqual(result.reloadAt, date(hour: 14))
    }

    func testStopsAtMidnight() {
        let result = schedule(5, at: date(hour: 23, minute: 10))
        // 23:10 (slot 46), then 23:30: the next slot would start tomorrow.
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.reloadAt, date(hour: 0).addingTimeInterval(86_400))
    }

    func testSchedulesAreDeterministic() {
        XCTAssertEqual(schedule(4, at: date(hour: 9)), schedule(4, at: date(hour: 9)))
    }
}
