import Foundation

/// Global authentication state, observed by `RootView`.
@MainActor
final class SessionStore: ObservableObject {
    /// Main screen to display.
    enum Phase: Equatable {
        case loggedOut
        case loggedIn(Credentials)
    }

    /// Login screen progress.
    enum LoginState: Equatable {
        case idle
        case connecting
        case waitingForApproval
    }

    @Published private(set) var phase: Phase = .loggedOut
    @Published private(set) var loginState: LoginState = .idle
    @Published var loginError: AppError?
    /// Nextcloud login page to present (non-nil ⇒ SFSafariViewController sheet shown).
    @Published var loginPage: URL?

    private let store = CredentialStore()
    private var loginTask: Task<Void, Never>?
    /// Clears the rest of the session (web data, local server), provided by the app.
    private let onSessionEnd: () -> Void

    init(onSessionEnd: @escaping () -> Void) {
        self.onSessionEnd = onSessionEnd
        // Restores the previous session; its validity is checked when the WebView loads.
        if let saved = store.load() {
            phase = .loggedIn(saved)
        }
    }

    // MARK: - Login

    /// Starts logging in to the entered server (validation, Login Flow v2, polling).
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
                // Deliberate cancellation: `cancelLogin` has already reset the state.
            } catch {
                guard let self else { return }
                self.loginPage = nil
                self.loginState = .idle
                self.loginError = AppError.from(error)
            }
        }
    }

    /// Cancels an ongoing login (user closed the browser).
    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginPage = nil
        loginState = .idle
    }

    // MARK: - Logout

    /// User-initiated logout: revokes the app password, clears the Keychain
    /// and the WebView data.
    func logout() {
        if case .loggedIn(let credentials) = phase {
            Task { await NextcloudClient().revokeAppPassword(credentials) }
        }
        endSession(error: nil)
    }

    /// Session rejected by the server (app password revoked, account deleted…).
    func sessionRevoked() {
        endSession(error: .notAuthenticated)
    }

    private func endSession(error: AppError?) {
        store.delete()
        onSessionEnd()
        loginError = error
        phase = .loggedOut
    }
}
