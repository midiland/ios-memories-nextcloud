import SwiftUI

/// App entry point and composition root: creates the shared services and wires them together.
@main
struct MemoriesApp: App {
    private let server: LocalHTTPServer
    @StateObject private var session: SessionStore

    init() {
        let server = LocalHTTPServer.shared
        self.server = server
        let teardown = SessionTeardown(server: server)
        _session = StateObject(wrappedValue: SessionStore(onSessionEnd: teardown.run))
    }

    var body: some Scene {
        WindowGroup {
            RootView(server: server)
                .environmentObject(session)
        }
    }
}
