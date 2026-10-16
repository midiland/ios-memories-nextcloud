import Foundation

/// Capture instant of a downloaded file, in the server's terms (`epoch`): the real instant when the
/// EXIF date has a timezone offset, otherwise the wall-clock time read as UTC (what the server
/// stores too). `PhotoMatcher` compares both forms with the device photos.
enum CaptureDate {
    /// Epoch from EXIF `DateTimeOriginal` (`2026:10:01 00:30:00`) and `OffsetTimeOriginal` (`+02:00`).
    static func epoch(exifDate: String, offset: String?) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let wallClock = formatter.date(from: String(exifDate.prefix(19))) else { return nil }
        let seconds = Int(wallClock.timeIntervalSince1970)
        guard let offset, let offsetSeconds = offsetSeconds(offset) else { return seconds }
        return seconds - offsetSeconds
    }

    /// `+02:00` / `-05:30` → seconds east of UTC.
    static func offsetSeconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let sign = trimmed.first, sign == "+" || sign == "-" else { return nil }
        let parts = trimmed.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let seconds = hours * 3_600 + minutes * 60
        return sign == "-" ? -seconds : seconds
    }
}
