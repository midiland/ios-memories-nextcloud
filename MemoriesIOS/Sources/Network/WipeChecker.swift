import Foundation

/// The remote-wipe operations of `NextcloudClient`, as a protocol so tests can mock them.
/// `NextcloudClient` conforms in its own file (retroactive conformance on a `final`
/// class is not reliably visible across files).
///
/// The wipe endpoints are `#[PublicPage]`: they take the server URL and the app
/// password (`token` form parameter), never the login name — so a pending wipe
/// (issue #15) only needs to persist those two values.
protocol WipeChecker {
    /// `true` when a remote wipe is pending for this app password.
    func checkWipe(server: ServerURL, token: String) async throws -> Bool
    /// Confirms the wipe to the server. Returns `true` on success, `false` on any error.
    func confirmWipe(server: ServerURL, token: String) async -> Bool
}
