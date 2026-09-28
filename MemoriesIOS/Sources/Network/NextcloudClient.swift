import Foundation

/// Minimal HTTP client for the Nextcloud endpoints the app needs:
/// Memories' `api/describe` and Login Flow v2.
///
/// Each instance has its own in-memory cookie storage (ephemeral session):
/// a Basic-authenticated request stores the Nextcloud session cookies there,
/// which are then copied into the WebView (see `WebSessionBootstrapper`).
final class NextcloudClient {
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        cookieStorage = config.httpCookieStorage ?? HTTPCookieStorage()
        session = URLSession(configuration: config)
    }

    // MARK: - api/describe

    /// Queries `api/describe`. With `credentials`, the request is Basic-authenticated
    /// and opens a server-side session (cookies available via `cookies(for:)`).
    ///
    /// Errors: server unreachable, Memories missing (404 or non-JSON response),
    /// credentials rejected (401), version too old.
    func describe(_ server: ServerURL, credentials: Credentials? = nil) async throws -> DescribeResponse {
        try await describeRaw(server, credentials: credentials, manifest: false).describe
    }

    /// Like `describe`, but also returns the raw JSON. With `manifest`, the response includes
    /// the JS (signed) and CSS manifests needed for the offline snapshot (`?manifest=1`).
    func describeRaw(
        _ server: ServerURL, credentials: Credentials?, manifest: Bool
    ) async throws -> (describe: DescribeResponse, raw: Data) {
        var url = server.describeURL
        if manifest, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "manifest", value: "1")]
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Without this header, Nextcloud may redirect to /login instead of returning 401.
        request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        request.setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")
        if let credentials {
            request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, status) = try await send(request)
        switch status {
        case 200: break
        case 401: throw AppError.notAuthenticated
        case 404: throw AppError.memoriesNotInstalled
        default: throw AppError.unexpectedStatus(status)
        }

        // A missing app can also show up as a redirect to an HTML page.
        guard let describe = try? JSONDecoder().decode(DescribeResponse.self, from: data) else {
            throw AppError.memoriesNotInstalled
        }
        if SemanticVersion(describe.version) < SemanticVersion(AppConstants.minServerVersion) {
            throw AppError.serverTooOld(version: describe.version)
        }
        return (describe, data)
    }

    // MARK: - Login Flow v2

    /// Starts Login Flow v2: returns the login page URL and the polling token.
    func startLoginFlow(_ loginFlowURL: URL) async throws -> LoginFlowInit {
        var request = URLRequest(url: loginFlowURL)
        request.httpMethod = "POST"
        request.setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")

        let (data, status) = try await send(request)
        guard status == 200 else { throw AppError.loginFlowUnavailable(status) }
        guard let flow = try? JSONDecoder().decode(LoginFlowInit.self, from: data) else {
            throw AppError.invalidResponse
        }
        return flow
    }

    /// A single polling attempt. `nil` until the user has approved (HTTP 404).
    func pollLogin(_ poll: LoginFlowInit.Poll) async throws -> LoginFlowResult? {
        var request = URLRequest(url: poll.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(poll.token)".data(using: .utf8)

        let (data, status) = try await send(request)
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(LoginFlowResult.self, from: data)
    }

    /// Revokes the app password on the server (best effort: errors are ignored,
    /// the local logout happens regardless).
    func revokeAppPassword(_ credentials: Credentials) async {
        let url = credentials.server.nextcloudRoot.appendingPathComponent("ocs/v2.php/core/apppassword")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        _ = try? await send(request)
    }

    // MARK: - Cookies

    /// Cookies received for the server host (Nextcloud session after an authenticated `describe`).
    func cookies(for server: ServerURL) -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return server.host == domain || server.host.hasSuffix("." + domain)
        }
    }

    // MARK: - Private

    /// Sends the request; any transport error becomes `serverUnreachable`.
    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            throw AppError.from(error)
        }
    }
}
