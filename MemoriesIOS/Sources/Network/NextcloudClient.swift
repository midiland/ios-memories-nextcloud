import Foundation

/// Client HTTP minimal pour les endpoints Nextcloud dont l'app a besoin :
/// `api/describe` de Memories et Login Flow v2.
///
/// Chaque instance a son propre stockage de cookies en mémoire (session éphémère) :
/// une requête authentifiée en Basic y dépose les cookies de session Nextcloud,
/// qu'on recopie ensuite dans la WebView (voir `WebSessionBootstrapper`).
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

    /// Interroge `api/describe`. Avec `credentials`, la requête est authentifiée en Basic
    /// et ouvre une session côté serveur (cookies récupérables via `cookies(for:)`).
    ///
    /// Erreurs : serveur injoignable, Memories absent (404 ou réponse non JSON),
    /// identifiants refusés (401), version trop ancienne.
    func describe(_ server: ServerURL, credentials: Credentials? = nil) async throws -> DescribeResponse {
        var request = URLRequest(url: server.describeURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Sans ce header, Nextcloud peut rediriger vers /login au lieu de répondre 401.
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

        // Une app absente peut aussi se traduire par une redirection vers une page HTML.
        guard let describe = try? JSONDecoder().decode(DescribeResponse.self, from: data) else {
            throw AppError.memoriesNotInstalled
        }
        if SemanticVersion(describe.version) < SemanticVersion(AppConstants.minServerVersion) {
            throw AppError.serverTooOld(version: describe.version)
        }
        return describe
    }

    // MARK: - Login Flow v2

    /// Démarre le Login Flow v2 : renvoie l'URL de la page de login et le jeton de polling.
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

    /// Une tentative de polling. `nil` tant que l'utilisateur n'a pas validé (HTTP 404).
    func pollLogin(_ poll: LoginFlowInit.Poll) async throws -> LoginFlowResult? {
        var request = URLRequest(url: poll.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(poll.token)".data(using: .utf8)

        let (data, status) = try await send(request)
        guard status == 200 else { return nil }
        return try? JSONDecoder().decode(LoginFlowResult.self, from: data)
    }

    /// Révoque le mot de passe d'application côté serveur (au mieux : les erreurs sont ignorées,
    /// la déconnexion locale a lieu dans tous les cas).
    func revokeAppPassword(_ credentials: Credentials) async {
        let url = credentials.server.nextcloudRoot.appendingPathComponent("ocs/v2.php/core/apppassword")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        _ = try? await send(request)
    }

    // MARK: - Cookies

    /// Cookies reçus pour l'hôte du serveur (session Nextcloud après un `describe` authentifié).
    func cookies(for server: ServerURL) -> [HTTPCookie] {
        (cookieStorage.cookies ?? []).filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return server.host == domain || server.host.hasSuffix("." + domain)
        }
    }

    // MARK: - Privé

    /// Envoie la requête ; toute erreur de transport devient `serverUnreachable`.
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
