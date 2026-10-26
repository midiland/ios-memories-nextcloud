import BackgroundTasks
import SwiftUI

/// App entry point and composition root: creates the shared services and wires them together.
@main
struct MemoriesApp: App {
    private let server: LocalHTTPServer
    @StateObject private var session: SessionStore
    private let memories = MemoryRefreshService()
    @StateObject private var deepLinks = DeepLinkRouter()

    init() {
        #if DEBUG
        DebugAutomation.seedCredentials()
        #endif
        // Before the session is restored from the Keychain.
        InstallMarker().purgeKeychainIfReinstalled()
        let server = LocalHTTPServer.shared
        self.server = server
        let teardown = SessionTeardown(server: server)
        _session = StateObject(wrappedValue: SessionStore(onSessionEnd: teardown.run))
    }

    var body: some Scene {
        WindowGroup {
            RootView(server: server, memories: memories)
                .environmentObject(session)
                .environmentObject(deepLinks)
                .onOpenURL { deepLinks.handle($0) }
        }
        // Periodic refresh of the widget's memories; iOS picks the actual time.
        .backgroundTask(.appRefresh(MemoryRefreshService.backgroundTaskIdentifier)) {
            await Self.scheduleMemoriesRefresh()
            guard let credentials = CredentialStore().load() else { return }
            await memories.refresh(credentials: credentials)
        }
    }

    /// Asks iOS for the next background refresh (re-submitted every time: a request fires once).
    static func scheduleMemoriesRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: MemoryRefreshService.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: MemoryRefreshService.backgroundInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
