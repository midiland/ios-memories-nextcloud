import SwiftUI

/// Écran principal une fois connecté : la WebView Memories, un indicateur de chargement,
/// l'écran d'erreur, et un menu natif (recharger / se déconnecter).
///
/// Le menu natif est provisoire : avec le pont NativeX, la déconnexion passera par
/// Paramètres > Compte > « Se déconnecter » dans l'UI web (`nativex.logout()`).
struct WebContainerView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model: WebViewModel
    @State private var confirmLogout = false

    init(credentials: Credentials) {
        _model = StateObject(wrappedValue: WebViewModel(credentials: credentials))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(.systemBackground).ignoresSafeArea()
            MemoriesWebView(model: model)

            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let error):
                ErrorView(error: error, retry: model.start, logout: { confirmLogout = true })
            case .ready:
                EmptyView()
            }

            menuButton
        }
        .onAppear {
            model.onSessionRevoked = { [weak session] in session?.sessionRevoked() }
            model.startIfNeeded()
        }
        .confirmationDialog("Se déconnecter de \(model.credentials.server.host) ?",
                            isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { session.logout() }
        }
    }

    /// Petit bouton flottant, placé au-dessus de la barre de navigation mobile de Memories.
    private var menuButton: some View {
        Menu {
            Text("\(model.credentials.loginName) — \(model.credentials.server.host)")
            Button { model.reload() } label: { Label("Recharger", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { confirmLogout = true } label: {
                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.trailing, 12)
        .padding(.bottom, 72)
        .accessibilityLabel("Menu du compte")
    }
}
