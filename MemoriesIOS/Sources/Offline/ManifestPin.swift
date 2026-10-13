import Foundation

/// Rollback protection for one account. A Memories 9 manifest has no version nor expiry, so a
/// server could replay an old, validly signed one (old web files with known bugs). Once a Memories 10
/// manifest (DSSE + TUF) has been accepted, the account only accepts DSSE manifests whose TUF
/// `version` (build time) is not lower than the highest one accepted. Cleared on logout.
struct ManifestPin: Codable, Equatable {
    /// Highest TUF targets version accepted for this account.
    let targetsVersion: Int

    /// Whether `manifest` may be used given the account's pin (`nil`: no DSSE manifest accepted yet).
    static func allows(_ manifest: AssetManifest, after pin: ManifestPin?) -> Bool {
        guard let pin else { return true }
        guard let targets = manifest.targets else { return false }
        return targets.version >= pin.targetsVersion
    }

    /// Pin to store once `manifest` is accepted: unchanged for a Memories 9 manifest.
    static func updated(_ pin: ManifestPin?, accepting manifest: AssetManifest) -> ManifestPin? {
        guard let targets = manifest.targets else { return pin }
        return ManifestPin(targetsVersion: max(targets.version, pin?.targetsVersion ?? .min))
    }
}
