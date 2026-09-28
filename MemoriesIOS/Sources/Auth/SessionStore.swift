import Foundation

/// État global d'authentification, observé par `RootView`.
@MainActor
final class SessionStore: ObservableObject {
    /// Écran principal à afficher.
    enum Phase: Equatable {
        case loggedOut
        case loggedIn(Credentials)
    }

    /// Progression de l'écran de connexion.
    enum LoginState: Equatable {
        case idle
        case connecting
        case waitingForApproval
    }

    @Published private(set) var phase: Phase = .loggedOut
    @Published private(set) var loginState: LoginState = .idle
    @Published var loginError: AppError?
    /// Page de login Nextcloud à présenter (non nil ⇒ feuille SFSafariViewController affichée).
    @Published var loginPage: URL?

    private let store = CredentialStore()
    private var loginTask: Task<Void, Never>?

    init() {
        // Restaure la session précédente ; sa validité est vérifiée au chargement de la WebView.
        if let saved = store.load() {
            phase = .loggedIn(saved)
        }
    }

    // MARK: - Connexion

    /// Lance la connexion au serveur saisi (validation, Login Flow v2, polling).
    func login(serverInput: String) {
        loginTask?.cancel()
        loginError = nil
        loginState = .connecting

        loginTask = Task { [weak self] in
            let flow = LoginFlowV2()
            do {
                let pending = try await flow.prepare(userInput: serverInput)
                guard let self, !Task.isCancelled else { return }
                self.loginPage = pending.loginPage
                self.loginState = .waitingForApproval

                let credentials = try await flow.waitForApproval(pending)
                try self.store.save(credentials)
                self.loginPage = nil
                self.loginState = .idle
                self.phase = .loggedIn(credentials)
            } catch is CancellationError {
                // Annulation volontaire : `cancelLogin` a déjà remis l'état à zéro.
            } catch {
                guard let self else { return }
                self.loginPage = nil
                self.loginState = .idle
                self.loginError = AppError.from(error)
            }
        }
    }

    /// Annule une connexion en cours (fermeture du navigateur par l'utilisateur).
    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginPage = nil
        loginState = .idle
    }

    // MARK: - Déconnexion

    /// Déconnexion volontaire : révoque le mot de passe d'application, efface le Keychain
    /// et les données de la WebView.
    func logout() {
        if case .loggedIn(let credentials) = phase {
            Task { await NextcloudClient().revokeAppPassword(credentials) }
        }
        endSession(error: nil)
    }

    /// Session refusée par le serveur (mot de passe d'application révoqué, compte supprimé…).
    func sessionRevoked() {
        endSession(error: .notAuthenticated)
    }

    private func endSession(error: AppError?) {
        store.delete()
        WebSessionBootstrapper.clearWebsiteData()
        loginError = error
        phase = .loggedOut
    }
}
