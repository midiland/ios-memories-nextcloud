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

    private let store: CredentialStore
    private let pendingWipeStore: PendingWipeStore
    private let dataWiper: DataWiper
    private var loginTask: Task<Void, Never>?
    /// Handles a 401 (revoked session): checks for a wipe, then tears down.
    private var revocationTask: Task<Void, Never>?
    /// Proactive wipe check (startup, foreground): never cancels a revocation.
    private var proactiveCheckTask: Task<Void, Never>?
    /// Last time a proactive wipe check was sent (rate-limit throttle: 10 req / 5 min / IP).
    private var lastProactiveCheck: Date?
    /// A remote wipe is running: the proactive check, the 401 handler and the pending-wipe
    /// resolution can all detect the same wipe, only the first one may run it.
    private var isWiping = false
    /// Clock for the throttle (injectable for tests).
    private let now: () -> Date
    /// Clears the rest of the session (web data, local server), provided by the app.
    private let onSessionEnd: () -> Void

    /// Wipe checker (injectable for tests).
    private let wipeChecker: WipeChecker
    /// Also used for `revokeAppPassword` on logout.
    private let client: NextcloudClient

    init(
        onSessionEnd: @escaping () -> Void,
        client: NextcloudClient = NextcloudClient(),
        wipeChecker: WipeChecker? = nil,
        dataWiper: DataWiper = DataWiper(),
        credentialStore: CredentialStore = CredentialStore(),
        pendingWipeStore: PendingWipeStore = PendingWipeStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.onSessionEnd = onSessionEnd
        self.client = client
        self.wipeChecker = wipeChecker ?? client
        self.dataWiper = dataWiper
        self.store = credentialStore
        self.pendingWipeStore = pendingWipeStore
        self.now = now
        // Restores the previous session; its validity is checked when the WebView loads.
        if let saved = store.load() {
            phase = .loggedIn(saved)
        }
        // Retries a wipe confirmation that failed on a previous launch, or resolves
        // a pending wipe after a 401 whose check could not run (network error).
        resolvePendingWipe()
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
            Task { await client.revokeAppPassword(credentials) }
        }
        endSession(error: nil)
    }

    // MARK: - Remote wipe (issue #15)

    /// Session rejected by the server (app password revoked, account deleted…).
    ///
    /// A token marked for remote wipe is rejected with 401, exactly like a revoked
    /// password. Before tearing down, we ask the server whether a wipe was requested:
    /// if so, all local data is erased (the wipe's purpose) and the wipe is confirmed.
    ///
    /// Idempotent: a second call while a revocation is already in progress is ignored,
    /// so `load()` and `refreshInBackground()` can both call it safely.
    ///
    /// If the check itself fails (network), the credentials are saved in a pending-wipe
    /// entry and the session ends: the user is not stuck on a dead session. The pending
    /// entry is resolved on the next launch (see `resolvePendingWipe`).
    func sessionRevoked() {
        guard case .loggedIn(let credentials) = phase else {
            endSession(error: .notAuthenticated)
            return
        }
        // Idempotent: ignore if a revocation is already in progress.
        guard revocationTask == nil else { return }
        revocationTask = Task { [weak self] in
            await self?.handleRevokedSession(credentials)
            self?.revocationTask = nil
        }
    }

    /// Proactively checks for a pending remote wipe (app launch, return to foreground).
    /// Throttled to at most one check per minute (the server rate-limits to
    /// 10 requests / 5 minutes / IP). Never cancels an ongoing revocation.
    func checkForRemoteWipe() {
        guard case .loggedIn(let credentials) = phase, !isWiping else { return }
        // Throttle: skip if the last check was less than a minute ago.
        if let last = lastProactiveCheck, now().timeIntervalSince(last) < 60 {
            return
        }
        lastProactiveCheck = now()
        proactiveCheckTask?.cancel()
        proactiveCheckTask = Task { [weak self] in
            await self?.checkWipe(credentials)
        }
    }

    // MARK: - Private

    /// On a 401: ask the server whether this is a remote wipe before tearing down.
    private func handleRevokedSession(_ credentials: Credentials) async {
        do {
            let wipeRequested = try await wipeChecker.checkWipe(credentials)
            guard !Task.isCancelled else { return }
            if wipeRequested {
                await performRemoteWipe(credentials)
            } else {
                endSession(error: .notAuthenticated)
            }
        } catch {
            // Network error: we cannot know whether a wipe was requested.
            // Save the credentials as a pending wipe and end the session: the user
            // gets the login screen, and the next launch resolves the pending entry
            // (wipe + confirm, or just delete the pending if no wipe was requested).
            guard !Task.isCancelled else { return }
            try? pendingWipeStore.save(credentials)
            endSession(error: .notAuthenticated)
        }
    }

    /// One proactive wipe check; does nothing when no wipe is pending.
    private func checkWipe(_ credentials: Credentials) async {
        do {
            let wipeRequested = try await wipeChecker.checkWipe(credentials)
            guard !Task.isCancelled, wipeRequested else { return }
            await performRemoteWipe(credentials)
        } catch {
            // Network error or rate limit: try again on the next launch / foreground.
        }
    }

    /// Erases all local data, confirms the wipe with the server, then ends the session.
    ///
    /// Order matters:
    /// 1. The pending entry is saved BEFORE the purge (which deletes the Keychain
    ///    credentials): if the app dies in between, the next launch can still confirm.
    /// 2. The UI leaves the Memories screen BEFORE the purge, so the web view and its
    ///    background tasks (snapshot sync, device-photo cache) stop writing to the disk.
    /// 3. The purge runs again after the confirmation (idempotent) to sweep anything a
    ///    task still in flight wrote in the meantime.
    private func performRemoteWipe(_ credentials: Credentials) async {
        guard !isWiping else { return }
        isWiping = true
        defer { isWiping = false }

        try? pendingWipeStore.save(credentials)
        store.delete()
        loginError = .remoteWipe
        phase = .loggedOut
        await dataWiper.run()
        let confirmed = await wipeChecker.confirmWipe(credentials)
        if confirmed {
            pendingWipeStore.delete()
        }
        // On failure the pending entry stays: the next launch retries the confirmation.
        await dataWiper.run()
        onSessionEnd()
    }

    /// Resolves a pending wipe left by a previous launch:
    /// - if a wipe is still requested, the local purge runs and the wipe is confirmed;
    /// - if no wipe is requested (e.g. the password was simply revoked), the pending
    ///   entry is deleted and the credentials are dropped.
    private func resolvePendingWipe() {
        guard let credentials = pendingWipeStore.load() else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let wipeRequested = try await self.wipeChecker.checkWipe(credentials)
                if wipeRequested {
                    // The local data may already be erased (previous launch) or not
                    // (401 path): run the purge again (idempotent) and confirm.
                    await self.performRemoteWipe(credentials)
                } else {
                    // No wipe: the pending entry was for a plain revocation.
                    self.pendingWipeStore.delete()
                }
            } catch {
                // Network error: keep the pending entry, retry on the next launch.
            }
        }
    }

    private func endSession(error: AppError?) {
        store.delete()
        onSessionEnd()
        loginError = error
        phase = .loggedOut
    }
}
