import SwiftUI

/// Switches between the login screen and the Memories app.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    let server: LocalHTTPServer
    let memories: MemoryRefreshService

    var body: some View {
        switch session.phase {
        case .loggedOut:
            LoginView()
        case .loggedIn(let credentials):
            WebContainerView(
                credentials: credentials,
                server: server,
                onSessionRevoked: { [weak session] in session?.sessionRevoked() },
                onLogout: { [weak session] in session?.logout() },
                onCheckRemoteWipe: { [weak session] in session?.checkForRemoteWipe() }
            )
                // New view identity per account: the WebView is recreated on every login.
                .id(credentials.loginName + "@" + credentials.server.memoriesURL.absoluteString)
                // Widget memories: refreshed in the foreground, next background run scheduled
                // when leaving. Restarts when the scene phase changes.
                .task(id: scenePhase) {
                    switch scenePhase {
                    case .active: await memories.refreshIfNeeded(credentials: credentials)
                    case .background: MemoriesApp.scheduleMemoriesRefresh()
                    default: break
                    }
                }
        }
    }
}
