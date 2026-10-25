import Foundation

/// Minimal HTTP client for the Nextcloud endpoints the app needs:
/// Memories' `api/describe`, Login Flow v2, and the remote-wipe endpoints.
///
/// Each instance uses an ephemeral session: nothing it receives (cookies, cache) outlives it.
final class NextcloudClient: WipeChecker {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - api/describe

    /// Queries `api/describe`. With `credentials`, the request is Basic-authenticated.
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

    // MARK: - Remote wipe (Nextcloud core/wipe)

    /// Checks whether a remote wipe was requested for this app password.
    ///
    /// `POST /index.php/core/wipe/check` with `token` as a form parameter (no Basic auth:
    /// the endpoint is `#[PublicPage]` and the token itself is the credential).
    /// Returns `true` on `200 {"wipe": true}`, `false` on `404` (no wipe pending).
    /// Throws on transport errors or unexpected statuses so the caller can retry later.
    func checkWipe(_ credentials: Credentials) async throws -> Bool {
        let request = wipeRequest("index.php/core/wipe/check", credentials)

        let (data, status) = try await send(request)
        switch status {
        case 200:
            // {"wipe": true} — a wipe is pending for this token.
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["wipe"] as? Bool == true
            else { throw AppError.invalidResponse }
            return true
        case 404:
            return false
        default:
            throw AppError.unexpectedStatus(status)
        }
    }

    /// Confirms a remote wipe to the server.
    ///
    /// `POST /index.php/core/wipe/success` with `token` as a form parameter.
    /// Returns `true` on HTTP 200 (the server marked the device as wiped) **and on 404**
    /// (the wipe was already confirmed, the token no longer exists — nothing left to do).
    /// Returns `false` only on transient errors (network, 429 rate limit, 5xx) so the
    /// caller can retry later.
    func confirmWipe(_ credentials: Credentials) async -> Bool {
        let request = wipeRequest("index.php/core/wipe/success", credentials)
        do {
            let (_, status) = try await send(request)
            // 200: wipe confirmed. 404: already confirmed (token gone) — both are success.
            return status == 200 || status == 404
        } catch {
            return false
        }
    }

    // MARK: - Private

    /// Form-encoded `POST` for the wipe endpoints: `token=<app password>`, percent-encoded so
    /// a `+`, `&` or `=` in the password cannot corrupt the body. No Basic auth: the
    /// endpoints are `#[PublicPage]` and the token itself is the credential.
    private func wipeRequest(_ path: String, _ credentials: Credentials) -> URLRequest {
        var request = URLRequest(url: credentials.server.nextcloudRoot.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        let token = credentials.appPassword.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = Data("token=\(token)".utf8)
        return request
    }

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
