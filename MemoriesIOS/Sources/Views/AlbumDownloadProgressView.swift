import SwiftUI

/// Persistent overlay shown while an album downloads (issue #14): download → extract →
/// save to Photos. Stays visible even when the initial toast has disappeared, so the user
/// always knows the process is still running.
struct AlbumDownloadProgressView: View {
    let progress: WebViewModel.DownloadProgress
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(progress.title ?? String(localized: "Downloading…"))
                .font(.headline)
                .multilineTextAlignment(.center)

            ProgressView(value: progress.fraction, total: 1)
                .frame(maxWidth: 280)

            Text(phaseText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if progress.total > 0 {
                Text("\(progress.done) / \(progress.total)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let onCancel {
                Button(String(localized: "Cancel"), action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var phaseText: String {
        switch progress.phase {
        case .downloading: return String(localized: "Downloading…")
        case .extracting: return String(localized: "Extracting…")
        case .savingToPhotos: return String(localized: "Saving to Photos…")
        }
    }

    private var accessibilityText: String {
        let base = progress.title ?? String(localized: "Downloading…")
        let phase = phaseText
        if progress.total > 0 {
            return "\(base), \(phase), \(progress.done) / \(progress.total)"
        }
        return "\(base), \(phase)"
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        AlbumDownloadProgressView(
            progress: .init(phase: .downloading, done: 45, total: 100, title: "Summer 2025"),
            onCancel: {}
        )
    }
}
