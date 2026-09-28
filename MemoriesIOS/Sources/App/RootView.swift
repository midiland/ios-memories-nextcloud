import SwiftUI

/// Aiguillage entre l'écran de connexion et l'app Memories.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        switch session.phase {
        case .loggedOut:
            LoginView()
        case .loggedIn(let credentials):
            WebContainerView(credentials: credentials)
                // Nouvelle identité de vue par compte : la WebView est recréée à chaque login.
                .id(credentials.loginName + "@" + credentials.server.memoriesURL.absoluteString)
        }
    }
}
