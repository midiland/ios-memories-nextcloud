import UIKit
import WebKit

/// Owns the `WKWebView` and drives its lifecycle:
/// - **local mode** (default): app served by the `127.0.0.1` server from an offline
///   snapshot → instant startup, works without network;
/// - **remote mode** (fallback): page loaded directly from Nextcloud, if the server
///   provides no signed manifest or the local server fails to start.
/// Also hosts the NativeX bridge (theme, toasts, logout, reload).
@MainActor
final class WebViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// First download of the Memories web files.
        case downloading(done: Int, total: Int)
        case ready
        case failed(AppError)
    }

    /// Temporary message shown over the web view (`nativex.toast`).
    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let long: Bool
    }

    @Published private(set) var state: State = .loading
    /// Background color of the web UI, painted behind the web view (which is transparent
    /// in native mode) and in the safe areas. `nil` = system background.
    @Published private(set) var themeColor: UIColor?
    @Published var toast: Toast?
    /// Whether the native back button is visible (pages without a web navigation bar, see `BackNavigationRule`).
    @Published private(set) var showsBackButton = false

    let credentials: Credentials
    let webView: WKWebView
    private(set) var mode: NavigationPolicy.Mode = .local

    /// Called when the server permanently rejects the credentials.
    let onSessionRevoked: () -> Void
    /// Called when the user logs out (web UI or error screen).
    let onLogout: () -> Void

    private let nativeX: NativeXController
    private let navigationHandler = WebNavigationHandler()
    private let offline: OfflineAppLoader
    private var lastBootstrap: Date?
    private var hasStarted = false
    /// Current load and background update check; cancelled by the next `start()`.
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var observations: [NSKeyValueObservation] = []

    init(
        credentials: Credentials,
        server: LocalHTTPServer,
        onSessionRevoked: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.credentials = credentials
        self.onSessionRevoked = onSessionRevoked
        self.onLogout = onLogout
        offline = OfflineAppLoader(credentials: credentials, server: server)
        nativeX = NativeXController(share: NativeXShareService(
            downloader: AuthenticatedDownloader(credentials: credentials),
            presentShareSheet: SharePresenter.present
        ))
        webView = WebViewFactory.make(bridge: nativeX)
        nativeX.host = self
        navigationHandler.model = self
        webView.navigationDelegate = navigationHandler
        webView.uiDelegate = navigationHandler
        observeHistory()
    }

    /// Tracks the URL and history (including Vue router `pushState` calls) for the back button.
    private func observeHistory() {
        let update: (WKWebView) -> Void = { [weak self] webView in
            Task { @MainActor in
                guard let self else { return }
                self.showsBackButton = BackNavigationRule.showsBackButton(
                    url: webView.url, canGoBack: webView.canGoBack, webRoot: self.credentials.server.webRoot
                )
            }
        }
        observations = [
            webView.observe(\.url, options: [.new]) { webView, _ in update(webView) },
            webView.observe(\.canGoBack, options: [.new]) { webView, _ in update(webView) },
        ]
    }

    /// Native back button: equivalent of Android's back button (`webview.goBack()`).
    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    private var cookieStore: WKHTTPCookieStore { webView.configuration.websiteDataStore.httpCookieStore }

    // MARK: - Loading

    /// First load (idempotent: `onAppear` may be called several times).
    func startIfNeeded() {
        guard !hasStarted else { return }
        start()
    }

    /// Loads the app: local mode if possible, otherwise remote fallback.
    /// A new call cancels the previous load (retry, expired session, `nativex.reload`),
    /// so two loads never race to update the state or the web view.
    func start() {
        loadTask?.cancel()
        refreshTask?.cancel()
        hasStarted = true
        state = .loading
        lastBootstrap = Date()
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// Cancels pending work when the screen goes away (logout, account change).
    func stop() {
        loadTask?.cancel()
        refreshTask?.cancel()
    }

    private func load() async {
        do {
            let progress: AssetSyncer.Progress = { [weak self] done, total in
                guard !Task.isCancelled else { return }
                self?.state = .downloading(done: done, total: total)
            }
            let localURL = try await offline.prepare(into: cookieStore, progress: progress)
            try Task.checkCancellation()
            if let localURL {
                mode = .local
                state = .loading
                webView.load(URLRequest(url: localURL))
                refreshTask = Task { [weak self] in await self?.refreshInBackground() }
            } else {
                try await startRemote()
            }
        } catch is CancellationError {
            // Superseded by a newer load.
        } catch AppError.notAuthenticated {
            guard !Task.isCancelled else { return }
            onSessionRevoked()
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(AppError.from(error))
        }
    }

    /// Remote mode (step 2a): Nextcloud session + `nx_auth` cookie, page loaded from the server.
    private func startRemote() async throws {
        mode = .remote
        try await WebSessionBootstrapper.bootstrap(credentials, into: cookieStore)
        try Task.checkCancellation()
        var request = URLRequest(url: credentials.server.memoriesURL)
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        webView.load(request)
    }

    /// Checks credentials and updates while the app runs on the cached snapshot.
    private func refreshInBackground() async {
        do {
            let updated = try await offline.refreshInBackground()
            guard updated, !Task.isCancelled else { return }
            webView.load(URLRequest(url: offline.entryURL))
            nativeXToast(String(localized: "Memories has been updated"), long: false)
        } catch AppError.notAuthenticated {
            guard !Task.isCancelled else { return }
            onSessionRevoked()
        } catch {
            // Offline or server unavailable: stay on the cached snapshot.
        }
    }

    /// Back in the foreground: iOS may have closed the local server's socket.
    func appDidBecomeActive() {
        guard hasStarted, mode == .local else { return }
        Task {
            if await offline.ensureServerRunning() {
                // New port = new origin: reload the entry page.
                webView.load(URLRequest(url: offline.entryURL))
            }
        }
    }

    // MARK: - Navigation events (called by WebNavigationHandler)

    /// Navigation rules for the current mode.
    var navigationPolicy: NavigationPolicy {
        let offline = offline
        return NavigationPolicy(
            mode: mode,
            serverHost: credentials.server.host,
            isLocal: { offline.isLocal($0) },
            serverPage: { offline.serverPage(for: $0) }
        )
    }

    func pageDidFinish() {
        state = .ready
        #if DEBUG
        DebugAutomation.run(on: self)
        #endif
    }

    func pageDidFail(_ error: AppError) {
        state = .failed(error)
    }

    /// The server redirected to its login page: the session has expired.
    /// Re-bootstrap once; if it loops again within 30 s, give up.
    func sessionLost() {
        if let last = lastBootstrap, Date().timeIntervalSince(last) < 30 {
            state = .failed(.notAuthenticated)
        } else {
            start()
        }
    }

    /// Opens an external link in the default app (Safari…).
    func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - NativeXHost

extension WebViewModel: NativeXHost {
    func nativeXSetTheme(color: UIColor?, isDark: Bool) {
        themeColor = color
    }

    func nativeXToast(_ message: String, long: Bool) {
        toast = Toast(message: message, long: long)
    }

    func nativeXLogout() {
        onLogout()
    }

    func nativeXReload() {
        start()
    }
}
