import Foundation

/// Global app constants.
enum AppConstants {
    /// Minimum server-side Memories version (same value as `min_server_version` on Android).
    static let minServerVersion = "9.0.0-rc.1"

    /// App version (CFBundleShortVersionString).
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// NativeX protocol version advertised to the server (`MemoriesNative/<v>`).
    /// Matches the Android app (versionName 1.15); the server requires ≥ `BinExt::NX_VER_MIN`
    /// (1.1), otherwise it returns the "app too old" page.
    static let nativeXVersion = "1.15"

    /// Suffix appended to the User-Agent of the WebView and native requests.
    /// `MemoriesNative/…` switches the server into native app mode (`Util::callerIsNative`):
    /// transparent template without sidebar, no preloading.
    static var userAgentSuffix: String { "MemoriesNative/\(nativeXVersion) MemoriesIOS/\(appVersion)" }

    /// Login Flow v2 polling interval and max duration (same as Android: 3 s / 10 min).
    static let loginPollInterval: UInt64 = 3_000_000_000
    static let loginPollTimeout: TimeInterval = 10 * 60
}
