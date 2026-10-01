import CryptoKit
import Foundation

/// Identifiers shared with the Memories server and frontend, computed exactly like the server
/// (`lib/Exif.php getBUID`, `TimelineWrite`) and the Android app (`PhotoMapper.kt`).
enum PhotoIDs {
    /// Content ID: `md5("<epoch><size>")`. Same capture instant and same file size ⇒ same file.
    static func auid(epoch: Int, size: Int64) -> String {
        md5Hex("\(epoch)\(size)")
    }

    /// Backup ID: `md5("<basename with extension>size=<size>")` (iPhone photos carry no EXIF ImageUniqueID).
    static func buid(basename: String, size: Int64) -> String {
        md5Hex("\(basename)size=\(size)")
    }

    /// Capture instant in whole seconds, as the server's `epoch` (`DateTime::getTimestamp`).
    static func epoch(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// Capture wall-clock time read as UTC, in seconds: what the server stores when the EXIF date
    /// has no timezone, and the basis of `dayid`.
    static func wallClockEpoch(_ date: Date, in timeZone: TimeZone) -> Int {
        epoch(date) + timeZone.secondsFromGMT(for: date)
    }

    /// Day of the capture wall-clock date: days since 1970-01-01 (server `dayid`).
    static func dayId(_ date: Date, in timeZone: TimeZone) -> Int {
        Int((Double(wallClockEpoch(date, in: timeZone)) / 86_400).rounded(.down))
    }

    /// Numeric file ID for a PhotoKit asset (the frontend requires numbers, `^/image/preview/\d+$`).
    /// Stable without storage, in `[2^52, 2^53)`: safe as a JS number and far above server file IDs.
    static func fileId(localIdentifier: String) -> Int64 {
        let digest = SHA256.hash(data: Data(localIdentifier.utf8))
        let low = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Int64(1 << 52) + Int64(low & ((1 << 52) - 1))
    }

    static func md5Hex(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
