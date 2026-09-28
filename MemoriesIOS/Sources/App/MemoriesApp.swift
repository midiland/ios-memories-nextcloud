import SwiftUI

/// Point d'entrée de l'app.
@main
struct MemoriesApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
    }
}
