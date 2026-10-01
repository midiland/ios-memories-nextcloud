import Foundation

/// Configuration of the locally served app: upstream server + current snapshot.
struct LocalAppConfig {
    let credentials: Credentials
    let snapshot: Snapshot
    /// User ID displayed by the frontend (`<head data-user>`).
    let user: String?
    /// Device photos (`/image/*`); `nil` if not available.
    var media: LocalMediaProvider?

    var server: ServerURL { credentials.server }
    var webRoot: String { server.webRoot }
}
