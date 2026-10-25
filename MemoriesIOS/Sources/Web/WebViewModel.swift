import UIKit
import WebKit

/// Owns the `WKWebView` and drives its lifecycle: the app is served by the `127.0.0.1` server
/// from a verified offline snapshot (instant startup, works without network). The web files are
/// never loaded from the server itself: if no verified snapshot can be served, the error screen
/// is shown instead.
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

    /// Progress of an ongoing album download (issue #14): shown as a persistent overlay
    /// while the download, extraction and saving to Photos run.
    struct DownloadProgress: Equatable {
        enum Phase: Equatable {
            case downloading
            case extracting
            case savingToPhotos
        }

        let phase: Phase
        let done: Int
        let total: Int
        let title: String?

        /// 0…1 for the progress bar; indeterminate (0) when `total` is 0.
        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(Double(done) / Double(total), 1)
        }
    }

    @Published private(set) var state: State = .loading
    /// Background color of the web UI, painted behind the web view (which is transparent
    /// in native mode) and in the safe areas. `nil` = system background.
    @Published private(set) var themeColor: UIColor?
    @Published var toast: Toast?
    /// Ongoing album download (issue #14): shown as a non-blocking banner at the bottom.
    @Published var downloadProgress: DownloadProgress?
    /// Whether the full download progress modal is open (tapped on the banner, issue #14).
    @Published var showsDownloadProgressModal = false
    /// The server offers a Memories update that does not verify: the app runs the previous version
    /// (banner at the top of the screen, see `UnverifiedUpdateBanner`).
    @Published private(set) var showsUnverifiedUpdateBanner = false
    /// Whether the native back button is visible (pages without a web navigation bar, see `BackNavigationRule`).
    @Published private(set) var showsBackButton = false
    /// The web photo viewer is open: the WebView extends over the safe areas (full screen,
    /// issue #13) so a zoomed photo can use the whole screen.
    @Published private(set) var viewerFullscreen = false

    let credentials: Credentials
    let webView: WKWebView

    /// Called when the server permanently rejects the credentials.
    let onSessionRevoked: () -> Void
    /// Called when the user logs out (web UI or error screen).
    let onLogout: () -> Void
    /// Called to proactively check for a pending remote wipe (issue #15):
    /// at startup and when the app returns to the foreground.
    let onCheckRemoteWipe: () -> Void

    /// The NativeX bridge (internal so the view can cancel an ongoing download, issue #14).
    private(set) var nativeX: NativeXController
    /// Device photos shown in the timeline.
    private let localPhotos: LocalTimeline
    private let navigationHandler = WebNavigationHandler()
    private let offline: OfflineAppLoader
    private var hasStarted = false
    /// The user closed the unverified-update banner: not shown again until the next launch.
    private var unverifiedUpdateBannerDismissed = false
    /// Scene in the foreground (the local server only listens then).
    private var isActive = true
    /// The WebContent process died: reload once the local server listens again.
    private var contentProcessTerminated = false
    /// A failed local load was already retried (reset by the next committed page).
    private var retriedLocalLoad = false
    /// Current load and background update check; cancelled by the next `start()`.
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var observations: [NSKeyValueObservation] = []

    init(
        credentials: Credentials,
        server: LocalHTTPServer,
        onSessionRevoked: @escaping () -> Void,
        onLogout: @escaping () -> Void,
        onCheckRemoteWipe: @escaping () -> Void = {}
    ) {
        self.credentials = credentials
        self.onSessionRevoked = onSessionRevoked
        self.onLogout = onLogout
        self.onCheckRemoteWipe = onCheckRemoteWipe
        let library = PhotoLibrary()
        localPhotos = LocalTimeline(credentials: credentials, library: library)
        offline = OfflineAppLoader(credentials: credentials, server: server, media: localPhotos)
        nativeX = NativeXController(
            share: NativeXShareService(
                downloader: AuthenticatedDownloader(credentials: credentials) { [weak server] in
                    server.map { LocalServerAccess(port: $0.port, secret: $0.secret) }
                },
                photoLibrary: library,
                presentShareSheet: SharePresenter.present
            ),
            photos: NativeXPhotoService(library: library),
            serverOrigin: credentials.server.origin,
            localPort: { [weak server] in server?.port ?? 0 }
        )
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
                    url: webView.url, canGoBack: webView.canGoBack, server: self.credentials.server
                )
            }
        }
        observations = [
            webView.observe(\.url, options: [.new]) { webView, _ in update(webView) },
            webView.observe(\.canGoBack, options: [.new]) { webView, _ in update(webView) },
        ]
    }

    /// Closes the unverified-update banner for this launch.
    func dismissUnverifiedUpdateBanner() {
        unverifiedUpdateBannerDismissed = true
        showsUnverifiedUpdateBanner = false
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

    /// Loads the app from the local server. A new call cancels the previous load
    /// (retry, `nativex.reload`), so two loads never race to update the state or the web view.
    func start() {
        loadTask?.cancel()
        refreshTask?.cancel()
        hasStarted = true
        state = .loading
        // Proactive remote-wipe check (issue #15): one cheap POST, well within the
        // server's rate limit (10 / 5 min / IP).
        onCheckRemoteWipe()
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
            nativeX.photos.timeline = localPhotos
            state = .loading
            // Like Android after signing in: offer device photos (and the iOS prompt) once.
            let url = nativeX.photos.takeSetupOffer() ? offline.setupURL : localURL
            webView.load(URLRequest(url: url))
            refreshTask = Task { [weak self] in await self?.refreshInBackground() }
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

    /// Checks credentials and updates while the app runs on the cached snapshot.
    private func refreshInBackground() async {
        do {
            let check = try await offline.refreshInBackground()
            guard !Task.isCancelled else { return }
            switch check {
            case .upToDate:
                break
            case .updated:
                showsUnverifiedUpdateBanner = false
                webView.load(URLRequest(url: offline.entryURL))
                nativeXToast(String(localized: "Memories has been updated"), long: false)
            case .unverifiable:
                // The server moved to web files this app cannot verify (e.g. a newer manifest
                // format): keep saying it, otherwise the old snapshot would silently drift from the server.
                showsUnverifiedUpdateBanner = !unverifiedUpdateBannerDismissed
            }
        } catch AppError.notAuthenticated {
            guard !Task.isCancelled else { return }
            onSessionRevoked()
        } catch {
            // Offline or server unavailable: stay on the cached snapshot.
        }
    }

    /// In the background: closes the local server's socket before iOS reclaims it.
    func appDidEnterBackground() {
        isActive = false
        guard hasStarted else { return }
        offline.suspendServer()
    }

    /// Back in the foreground: listens again (same port, so the page keeps working), then
    /// reloads what the background broke (see `LocalReloadRule`). Also checks for a
    /// pending remote wipe (issue #15).
    func appDidBecomeActive() {
        isActive = true
        guard hasStarted else { return }
        onCheckRemoteWipe()
        Task { await recoverLocalPage() }
    }

    /// Restarts the local server if needed, then reloads the page if it was lost.
    private func recoverLocalPage() async {
        guard let port = await offline.ensureServerRunning(), isActive else { return }
        let page = webView.url.flatMap { offline.isLocal($0) ? $0 : nil }
        var showsUnreachableError = false
        if case .failed(.serverUnreachable) = state { showsUnreachableError = true }
        let action = LocalReloadRule.onBecomeActive(
            page: page, serverPort: port,
            contentProcessTerminated: contentProcessTerminated, showsUnreachableError: showsUnreachableError
        )
        contentProcessTerminated = false
        switch action {
        case .none: break
        case .reload: webView.reload()
        // Port taken by another app = new origin: reload the entry page.
        case .loadEntry: webView.load(URLRequest(url: offline.entryURL))
        case .restart: start()
        }
    }

    // MARK: - Navigation events (called by WebNavigationHandler)

    /// Navigation rules (only local-server pages stay in the web view).
    var navigationPolicy: NavigationPolicy {
        let offline = offline
        return NavigationPolicy(
            isLocal: { offline.isLocal($0) },
            serverPage: { offline.serverPage(for: $0) }
        )
    }

    func pageDidFinish() {
        state = .ready
        retriedLocalLoad = false
        #if DEBUG
        DebugAutomation.run(on: self)
        #endif
    }

    func pageDidFail(_ error: AppError) {
        state = .failed(error)
    }

    /// Main-frame load error. A connection error usually means the local server was not
    /// listening yet (return from the background): restart it and retry once.
    func pageDidFail(loading error: Error) {
        guard LocalReloadRule.shouldRetry(error, alreadyRetried: retriedLocalLoad) else {
            return pageDidFail(.serverUnreachable(error.localizedDescription))
        }
        retriedLocalLoad = true
        Log.web.notice("Local page load failed, retrying once the server listens")
        contentProcessTerminated = true
        guard isActive else { return } // retried by appDidBecomeActive()
        Task { await recoverLocalPage() }
    }

    /// The WebContent process was killed (memory pressure, often while in the background).
    /// The reload waits for the local server, which does not listen in the background.
    func webContentProcessDidTerminate() {
        Log.web.notice("WebContent process terminated")
        contentProcessTerminated = true
        guard isActive else { return } // reloaded by appDidBecomeActive()
        Task { await recoverLocalPage() }
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

    func nativeXSetDownloadProgress(_ progress: DownloadProgress?) {
        downloadProgress = progress
    }

    /// Cancels the ongoing album download (issue #14).
    func cancelDownload() {
        nativeX.cancelDownload()
        downloadProgress = nil
        showsDownloadProgressModal = false
    }

    /// Opens the full download progress modal (tapped on the banner, issue #14).
    func showDownloadProgressModal() {
        showsDownloadProgressModal = true
    }

    /// Closes the full download progress modal (issue #14).
    func hideDownloadProgressModal() {
        showsDownloadProgressModal = false
    }

    func nativeXLogout() {
        onLogout()
    }

    func nativeXReload() {
        start()
    }

    func nativeXEvaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func nativeXSetViewerFullscreen(_ fullscreen: Bool) {
        viewerFullscreen = fullscreen
    }
}
