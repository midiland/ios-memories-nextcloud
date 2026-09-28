import SwiftUI

/// First launch on a server: downloading the Memories web files
/// (native equivalent of `waiting.html` on Android).
struct DownloadProgressView: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(maxWidth: 240)
            Text("Préparation de Memories…")
                .font(.headline)
            Text(total > 0 ? "\(done) / \(total) fichiers" : "Connexion au serveur")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
