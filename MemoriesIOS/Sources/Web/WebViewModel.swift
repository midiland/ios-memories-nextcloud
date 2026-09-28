import UIKit
import WebKit

/// Possède la `WKWebView` et pilote son cycle de vie :
/// - **mode local** (par défaut) : app servie par le serveur `127.0.0.1` depuis un snapshot
///   hors ligne → démarrage instantané, fonctionne sans réseau ;
/// - **mode distant** (repli) : page chargée directement depuis Nextcloud, si le serveur
///   ne fournit pas de manifeste signé ou si le serveur local ne démarre pas.
/// C'est aussi l'hôte du pont NativeX (thème, toasts, déconnexion, rechargement).
@MainActor
final class WebViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        /// Premier téléchargement des fichiers web de Memories.
        case downloading(done: Int, total: Int)
        case ready
        case failed(AppError)
    }

    enum Mode {
        case local
        case remote
    }

    /// Message temporaire affiché par-dessus la WebView (`nativex.toast`).
    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let long: Bool
    }

    @Published private(set) var state: State = .loading
    /// Couleur de fond de l'UI web, peinte derrière la WebView (qui est transparente
    /// en mode natif) et dans les zones de sécurité. `nil` = fond système.
    @Published private(set) var themeColor: UIColor?
    @Published var toast: Toast?
    /// Bouton retour natif visible (pages sans barre de navigation web, voir `BackNavigationRule`).
    @Published private(set) var showsBackButton = false

    let credentials: Credentials
    let webView: WKWebView
    private(set) var mode: Mode = .local

    /// Appelé quand le serveur refuse définitivement les identifiants.
    var onSessionRevoked: () -> Void = {}
    /// Appelé quand l'utilisateur se déconnecte depuis l'UI web.
    var onLogout: () -> Void = {}

    private let nativeX = NativeXController()
    private let navigationHandler = WebNavigationHandler()
    private let offline: OfflineAppLoader
    private var lastBootstrap: Date?
    private var hasStarted = false
    private var observations: [NSKeyValueObservation] = []

    init(credentials: Credentials) {
        self.credentials = credentials
        offline = OfflineAppLoader(credentials: credentials)
        webView = WebViewFactory.make(bridge: nativeX)
        nativeX.host = self
        navigationHandler.model = self
        webView.navigationDelegate = navigationHandler
        webView.uiDelegate = navigationHandler
        observeHistory()
    }

    /// Suit l'URL et l'historique (y compris les `pushState` du routeur Vue) pour le bouton retour.
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

    /// Bouton retour natif : équivalent du bouton « retour » d'Android (`webview.goBack()`).
    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    private var cookieStore: WKHTTPCookieStore { webView.configuration.websiteDataStore.httpCookieStore }

    // MARK: - Chargement

    /// Premier chargement (idempotent : `onAppear` peut être appelé plusieurs fois).
    func startIfNeeded() {
        guard !hasStarted else { return }
        start()
    }

    /// Charge l'app : mode local si possible, sinon repli distant.
    func start() {
        hasStarted = true
        state = .loading
        lastBootstrap = Date()
        Task {
            do {
                let progress: AssetSyncer.Progress = { [weak self] done, total in
                    self?.state = .downloading(done: done, total: total)
                }
                if let url = try await offline.prepare(into: cookieStore, progress: progress) {
                    mode = .local
                    state = .loading
                    webView.load(URLRequest(url: url))
                    Task { await refreshInBackground() }
                } else {
                    try await startRemote()
                }
            } catch AppError.notAuthenticated {
                onSessionRevoked()
            } catch {
                state = .failed(AppError.from(error))
            }
        }
    }

    /// Mode distant (étape 2a) : session Nextcloud + cookie `nx_auth`, page chargée depuis le serveur.
    private func startRemote() async throws {
        mode = .remote
        try await WebSessionBootstrapper.bootstrap(credentials, into: cookieStore)
        var request = URLRequest(url: credentials.server.memoriesURL)
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        webView.load(request)
    }

    /// Vérifie identifiants et mises à jour pendant que l'app tourne sur le snapshot en cache.
    private func refreshInBackground() async {
        do {
            if try await offline.refreshInBackground() {
                webView.load(URLRequest(url: offline.entryURL))
                nativeXToast("Memories a été mis à jour", long: false)
            }
        } catch AppError.notAuthenticated {
            onSessionRevoked()
        } catch {
            // Hors ligne ou serveur indisponible : on reste sur le snapshot en cache.
        }
    }

    /// Retour au premier plan : iOS a pu fermer le socket du serveur local.
    func appDidBecomeActive() {
        guard hasStarted, mode == .local else { return }
        Task {
            if await offline.ensureServerRunning() {
                // Nouveau port = nouvelle origine : on recharge la page d'entrée.
                webView.load(URLRequest(url: offline.entryURL))
            }
        }
    }

    // MARK: - Événements de navigation (appelés par WebNavigationHandler)

    /// Décide du sort d'une navigation de page.
    func decideNavigation(to url: URL) -> WebNavigationHandler.Decision {
        switch mode {
        case .local:
            guard Self.isLoopback(url) else { return .external(url) }
            // Chemin relayé (ex. lien vers une autre app Nextcloud) : ouvrir la vraie page dans Safari.
            if let real = LocalHTTPServer.shared.router.browserURL(forPath: url.path, query: url.query) {
                return .external(real)
            }
            return .allow
        case .remote:
            guard url.host == credentials.server.host else { return .external(url) }
            return WebNavigationHandler.isLoginPage(url) ? .sessionLost : .allow
        }
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

    /// Le serveur a redirigé vers sa page de login : la session a expiré.
    /// On réamorce une fois ; si ça reboucle en moins de 30 s, on abandonne.
    func sessionLost() {
        if let last = lastBootstrap, Date().timeIntervalSince(last) < 30 {
            state = .failed(.notAuthenticated)
        } else {
            start()
        }
    }

    /// Ouvre un lien externe dans l'app par défaut (Safari…).
    func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private static func isLoopback(_ url: URL) -> Bool {
        url.host == LocalHTTPServer.host || url.host == "localhost"
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
