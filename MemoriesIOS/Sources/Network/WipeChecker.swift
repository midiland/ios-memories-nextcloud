import Foundation

/// The remote-wipe operations of `NextcloudClient`, as a protocol so tests can mock them.
/// `NextcloudClient` conforms in its own file (retroactive conformance on a `final`
/// class is not reliably visible across files).
protocol WipeChecker {
    /// `true` when a remote wipe is pending for these credentials.
    func checkWipe(_ credentials: Credentials) async throws -> Bool
    /// Confirms the wipe to the server. Returns `true` on success, `false` on any error.
    func confirmWipe(_ credentials: Credentials) async -> Bool
}
