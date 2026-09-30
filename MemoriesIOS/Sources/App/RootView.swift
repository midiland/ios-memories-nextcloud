import SwiftUI

/// Switches between the login screen and the Memories app.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    let server: LocalHTTPServer

    var body: some View {
        switch session.phase {
        case .loggedOut:
            LoginView()
        case .loggedIn(let credentials):
            WebContainerView(
                credentials: credentials,
                server: server,
                onSessionRevoked: { [weak session] in session?.sessionRevoked() },
                onLogout: { [weak session] in session?.logout() }
            )
                // New view identity per account: the WebView is recreated on every login.
                .id(credentials.loginName + "@" + credentials.server.memoriesURL.absoluteString)
        }
    }
}
