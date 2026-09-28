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
            Text("Preparing Memories…")
                .font(.headline)
            // Two literals rather than a ternary: only literals are looked up in the catalog.
            // Runtime key is "%lld / %lld files" (Xcode's static extractor may guess "%@").
            Group {
                if total > 0 { Text("\(done) / \(total) files") } else { Text("Connecting to the server") }
            }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
