import Foundation

/// Hands links opened from outside the app (the widget) to the web view screen, which may not
/// exist yet: a link received while logged out waits for the login.
@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published private(set) var memory: MemoryDeepLink?

    func handle(_ url: URL) {
        if let link = MemoryDeepLink(url: url) { memory = link }
    }

    /// Takes the pending link, so it is only followed once.
    func takeMemory() -> MemoryDeepLink? {
        defer { memory = nil }
        return memory
    }
}
