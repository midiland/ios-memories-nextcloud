import Foundation

/// Device photos known to have a copy on the server, persisted per account
/// (`Application Support/photos/<account>.json`). Used when the server cannot be reached
/// (offline) and to count only the device-only photos of each day.
final class RemoteCopyStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var identifiers: Set<String>

    init(credentials: Credentials, directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photos", isDirectory: true)
        let account = "\(credentials.loginName)@\(credentials.server.host)"
        let safe = String(account.map { $0.isLetter || $0.isNumber || "._-@".contains($0) ? $0 : "_" })
        fileURL = base.appendingPathComponent(safe + ".json")
        let data = try? Data(contentsOf: fileURL)
        identifiers = data.flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    func contains(_ localIdentifier: String) -> Bool {
        lock.withLock { identifiers.contains(localIdentifier) }
    }

    /// Records the result of a match for these photos: `matched` have a server copy, the others not.
    func update(checked: [String], matched: Set<String>) {
        let changed = lock.withLock { () -> Bool in
            let before = identifiers
            identifiers.subtract(checked)
            identifiers.formUnion(matched)
            return identifiers != before
        }
        if changed { save() }
    }

    func insert(_ localIdentifiers: [String]) {
        let changed = lock.withLock { () -> Bool in
            let before = identifiers.count
            identifiers.formUnion(localIdentifiers)
            return identifiers.count != before
        }
        if changed { save() }
    }

    private func save() {
        let snapshot = lock.withLock { identifiers }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            Log.photos.error("Cannot save remote copies: \(String(describing: error), privacy: .public)")
        }
    }
}
