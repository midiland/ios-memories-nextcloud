import Foundation

/// Detects a fresh install on a device whose Keychain still holds the previous install's items
/// (the iOS Keychain survives uninstalling): without this, a reinstall would silently log in with
/// the old app password while snapshots, pins and preferences are gone.
///
/// A marker in `UserDefaults` tells installs apart. It is created on first launch and survives
/// logout and remote wipe (`DataWiper` keeps it), otherwise the next launch after a logout and a
/// new login would erase the new credentials.
struct InstallMarker {
    static let key = "installMarker"

    var defaults: UserDefaults = .standard

    /// Runs `purge` if this launch is the first of a fresh install, then sets the marker.
    /// `hasExistingAppData` tells an update from a version that predates the marker (the
    /// user keeps the session) from a reinstall (no app data left, only the Keychain).
    @discardableResult
    func purgeKeychainIfReinstalled(
        hasExistingAppData: () -> Bool = { SnapshotStore().hasData },
        purge: () -> Void = {
            CredentialStore().delete()
            PendingWipeStore().delete()
        }
    ) -> Bool {
        guard !defaults.bool(forKey: Self.key) else { return false }
        defer { defaults.set(true, forKey: Self.key) }
        guard !hasExistingAppData() else { return false }
        purge()
        return true
    }
}
