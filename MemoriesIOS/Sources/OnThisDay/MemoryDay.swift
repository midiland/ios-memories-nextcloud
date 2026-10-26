import Foundation

/// Server day ids (`floor(epoch / 86400)`). Shared with the widget target.
enum MemoryDay {
    /// Fixed UTC calendar: day ids are UTC-based, the frontend shifts "now" to local time first.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Seconds in a day.
    static let seconds = 86_400

    /// Day id of the calendar day of `date` in `calendar` (the user's local day).
    static func id(of date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let local = DateComponents(calendar: utc, year: c.year, month: c.month, day: c.day)
        return Int(utc.date(from: local)!.timeIntervalSince1970) / seconds
    }
}
