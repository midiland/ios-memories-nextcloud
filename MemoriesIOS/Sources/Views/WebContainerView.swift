import SwiftUI

/// Écran principal une fois connecté : la WebView Memories en « mode app ».
///
/// - En mode natif, la page web est transparente : le fond peint ici (couleur envoyée
///   par `nativex.setThemeColor`) apparaît derrière elle et dans les zones de sécurité
///   (encoche, barre d'accueil), comme la vue racine thémée d'Android.
/// - La déconnexion se fait dans l'UI web (Paramètres > Compte), ou depuis l'écran d'erreur.
struct WebContainerView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: WebViewModel

    init(credentials: Credentials) {
        _model = StateObject(wrappedValue: WebViewModel(credentials: credentials))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()
            MemoriesWebView(model: model)

            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .downloading(let done, let total):
                DownloadProgressView(done: done, total: total)
            case .failed(let error):
                ErrorView(error: error, retry: model.start, logout: session.logout)
            case .ready:
                EmptyView()
            }

            if let toast = model.toast {
                ToastView(message: toast.message)
                    .id(toast.id)
                    .task(id: toast.id) { await dismiss(toast) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .onAppear {
            model.onSessionRevoked = { [weak session] in session?.sessionRevoked() }
            model.onLogout = { [weak session] in session?.logout() }
            model.startIfNeeded()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.appDidBecomeActive() }
        }
    }

    private var background: Color {
        model.themeColor.map(Color.init(uiColor:)) ?? Color(.systemBackground)
    }

    /// Masque le toast après 2 s (ou 3,5 s pour un toast « long »), comme Android.
    private func dismiss(_ toast: WebViewModel.Toast) async {
        try? await Task.sleep(nanoseconds: toast.long ? 3_500_000_000 : 2_000_000_000)
        if model.toast == toast { model.toast = nil }
    }
}
