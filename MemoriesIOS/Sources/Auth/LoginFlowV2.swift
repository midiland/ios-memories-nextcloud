import Foundation

/// Nextcloud login via Login Flow v2, in two steps (like `AccountManager` on Android):
/// 1. `prepare`: checks the server (`api/describe`), then opens a flow → login URL;
/// 2. `waitForApproval`: polls every 3 s (10 min max) until `loginName` +
///    `appPassword` are obtained.
///
/// Presenting the login page (SFSafariViewController) is handled by the view.
struct LoginFlowV2 {
    /// Ready flow: page to open + polling info.
    struct Pending {
        let loginPage: URL
        let poll: LoginFlowInit.Poll
        /// Canonical Memories root returned by the server.
        let server: ServerURL
    }

    private let client = NextcloudClient()

    /// Validates the entered server and starts a flow.
    func prepare(userInput: String) async throws -> Pending {
        guard let entered = ServerURL(userInput: userInput) else { throw AppError.invalidURL }

        let describe = try await client.describe(entered)
        // The server knows its canonical URL (overwrite.cli.url, protocol…): prefer it, as long
        // as it stays on the entered host (the app password goes to the host chosen here).
        var server = entered
        if ServerURL(memoriesBaseURL: describe.baseUrl) != nil {
            guard let canonical = LoginURLPolicy.canonicalServer(baseUrl: describe.baseUrl, entered: entered) else {
                throw AppError.invalidResponse
            }
            server = canonical
        }
        guard let loginFlowURL = URL(string: describe.loginFlowUrl),
              LoginURLPolicy.isAcceptable(loginFlowURL, for: server)
        else { throw AppError.invalidResponse }

        let flow = try await client.startLoginFlow(loginFlowURL)
        // Opened in Safari and polled: both must be web URLs on the server's host.
        guard LoginURLPolicy.isAcceptable(flow.login, for: server),
              LoginURLPolicy.isAcceptable(flow.poll.endpoint, for: server)
        else { throw AppError.invalidResponse }
        return Pending(loginPage: flow.login, poll: flow.poll, server: server)
    }

    /// Waits for the user to approve the login in the browser.
    /// Stops cleanly if the task is cancelled (`CancellationError`).
    func waitForApproval(_ pending: Pending) async throws -> Credentials {
        let deadline = Date().addingTimeInterval(AppConstants.loginPollTimeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: AppConstants.loginPollInterval)
            // Transient network errors are ignored: retry on the next round.
            if let result = try? await client.pollLogin(pending.poll) {
                return Credentials(
                    server: pending.server,
                    loginName: result.loginName,
                    appPassword: result.appPassword
                )
            }
        }
        throw AppError.loginTimeout
    }
}
