import UIKit
import WebKit

/// Possède la `WKWebView` et pilote son cycle de vie : amorçage de la session,
/// chargement de Memories, erreurs, reconnexion automatique.
/// C'est aussi l'hôte du pont NativeX (thème, toasts, déconnexion, rechargement).
@MainActor
final class WebViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case failed(AppError)
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

    let credentials: Credentials
    let webView: WKWebView

    /// Appelé quand le serveur refuse définitivement les identifiants.
    var onSessionRevoked: () -> Void = {}
    /// Appelé quand l'utilisateur se déconnecte depuis l'UI web.
    var onLogout: () -> Void = {}

    private let nativeX = NativeXController()
    private let navigationHandler = WebNavigationHandler()
    private var lastBootstrap: Date?
    private var hasStarted = false

    init(credentials: Credentials) {
        self.credentials = credentials
        webView = WebViewFactory.make(bridge: nativeX)
        nativeX.host = self
        navigationHandler.model = self
        webView.navigationDelegate = navigationHandler
        webView.uiDelegate = navigationHandler
    }

    // MARK: - Chargement

    /// Premier chargement (idempotent : `onAppear` peut être appelé plusieurs fois).
    func startIfNeeded() {
        guard !hasStarted else { return }
        start()
    }

    /// (Ré)authentifie la WebView puis charge l'app Memories.
    func start() {
        hasStarted = true
        state = .loading
        lastBootstrap = Date()
        Task {
            do {
                try await WebSessionBootstrapper.bootstrap(
                    credentials, into: webView.configuration.websiteDataStore.httpCookieStore
                )
                var request = URLRequest(url: credentials.server.memoriesURL)
                // Secours si un cookie n'a pas pris : Nextcloud accepte aussi le Basic auth.
                request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
                webView.load(request)
            } catch AppError.notAuthenticated {
                onSessionRevoked()
            } catch {
                state = .failed(AppError.from(error))
            }
        }
    }

    // MARK: - Événements de navigation (appelés par WebNavigationHandler)

    func pageDidFinish() {
        state = .ready
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
