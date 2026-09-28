import SwiftUI

/// Premier lancement sur un serveur : téléchargement des fichiers web de Memories
/// (équivalent natif de `waiting.html` sur Android).
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
