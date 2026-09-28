import UIKit
import WebKit

/// Possède la `WKWebView` et pilote son cycle de vie : amorçage de la session,
/// chargement de Memories, erreurs, reconnexion automatique.
@MainActor
final class WebViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case failed(AppError)
    }

    @Published private(set) var state: State = .loading

    let credentials: Credentials
    let webView: WKWebView

    /// Appelé quand le serveur refuse définitivement les identifiants.
    var onSessionRevoked: () -> Void = {}

    private let bridge: NativeXBridge
    private let navigationHandler = WebNavigationHandler()
    private var lastBootstrap: Date?
    private var hasStarted = false

    init(credentials: Credentials, bridge: NativeXBridge? = nil) {
        self.credentials = credentials
        let bridge = bridge ?? DisabledNativeXBridge()
        self.bridge = bridge
        webView = WebViewFactory.make(bridge: bridge)
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

    /// Recharge la page courante (ou relance tout si on est en erreur).
    func reload() {
        if case .failed = state { start() } else { webView.reload() }
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
