import Foundation
import WebKit

/// Erases every trace of the account from the device, for a Nextcloud remote wipe
/// (Security → Devices & sessions → "Wipe device", issue #15).
///
/// Unlike `SessionTeardown` (normal logout, which keeps the offline snapshots so the
/// next sign-in is instant), a remote wipe must remove everything: the wipe exists
/// precisely because the device may be lost or stolen.
///
/// The order matters: the Keychain credentials are deleted last. The caller keeps its own
/// copy in memory (and in `PendingWipeStore`) to confirm the wipe with `/core/wipe/success`.
/// `run()` is idempotent: it can safely be repeated to sweep anything written meanwhile.
///
/// Photos already saved to the iOS Photos library are intentionally left alone:
/// that is the user's photo library, and the app has no right to erase it silently.
struct DataWiper {
    private let fileManager: FileManager
    private let appSupport: URL
    private let caches: URL
    private let temporary: URL
    private let defaults: UserDefaults
    /// Persistent domain cleared by `removeUserDefaults` (the app's bundle id, or a test suite name).
    private let defaultsDomain: String
    private let credentialStore: CredentialStore

    init(
        fileManager: FileManager = .default,
        appSupport: URL? = nil,
        caches: URL? = nil,
        temporary: URL? = nil,
        defaults: UserDefaults = .standard,
        defaultsDomain: String = Bundle.main.bundleIdentifier ?? "",
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.fileManager = fileManager
        self.appSupport = appSupport
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.caches = caches
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.temporary = temporary ?? fileManager.temporaryDirectory
        self.defaults = defaults
        self.defaultsDomain = defaultsDomain
        self.credentialStore = credentialStore
    }

    /// Erases all local data. Safe to call once; every step is best-effort.
    /// Awaits the WebKit data removal so the wipe is complete before the caller
    /// confirms it with the server.
    func run() async {
        removeSnapshots()
        removeRemoteCopies()
        removeTemporaryFiles()
        removeCaches()
        clearURLCache()
        removeUserDefaults()
        await clearWebViewData()
        clearCookies()
        removeCredentials()
    }

    // MARK: - Private

    /// `Application Support/offline/` — the downloaded web app snapshots.
    private func removeSnapshots() {
        let offline = appSupport.appendingPathComponent("offline", isDirectory: true)
        try? fileManager.removeItem(at: offline)
    }

    /// `Application Support/photos/` — the RemoteCopyStore JSON files.
    private func removeRemoteCopies() {
        let photos = appSupport.appendingPathComponent("photos", isDirectory: true)
        try? fileManager.removeItem(at: photos)
    }

    /// `temporaryDirectory/` — in-flight downloads and extractions.
    private func removeTemporaryFiles() {
        let contents = (try? fileManager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    /// `Caches/` — WebKit and system caches.
    private func removeCaches() {
        let contents = (try? fileManager.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }

    private func clearURLCache() {
        URLCache.shared.removeAllCachedResponses()
    }

    /// Removes the app's whole UserDefaults domain, so a key added later is erased too.
    /// Only the app's own persistent domain is cleared: unlike iterating over
    /// `dictionaryRepresentation()`, this leaves the system's global keys alone.
    /// Keeps the install marker (a bare flag, no personal data): see `InstallMarker`.
    private func removeUserDefaults() {
        guard !defaultsDomain.isEmpty else { return }
        let marker = defaults.bool(forKey: InstallMarker.key)
        defaults.removePersistentDomain(forName: defaultsDomain)
        if marker { defaults.set(true, forKey: InstallMarker.key) }
    }

    /// WebView data: localStorage, IndexedDB, service workers, disk cache…
    /// WebKit must be used from the main thread (calling it from the cooperative pool
    /// crashes inside `InitializeWebKit2`), hence `@MainActor`. Awaits the completion
    /// handler so the wipe is complete before the caller confirms it with the server.
    @MainActor
    private func clearWebViewData() async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }

    /// Nextcloud session cookies held by the local server's upstream proxy.
    private func clearCookies() {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    /// Keychain credentials — last, the caller may still need them for `confirmWipe`.
    private func removeCredentials() {
        credentialStore.delete()
    }
}
