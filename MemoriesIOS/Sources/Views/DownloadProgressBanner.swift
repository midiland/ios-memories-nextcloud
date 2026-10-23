import SwiftUI

/// Non-blocking banner shown at the top while an album downloads (issue #14), in the same
/// style as `UnverifiedUpdateBanner`: it pushes the web view down, so the user can keep
/// navigating the app. Tapping it opens the full progress modal (`AlbumDownloadProgressView`);
/// the ✕ button cancels the download.
struct DownloadProgressBanner: View {
    let progress: WebViewModel.DownloadProgress
    let onTap: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Phase icon.
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                // Title.
                Text(progress.title ?? String(localized: "Downloading…"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                // Progress bar + phase/counter.
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction, total: 1)

                    if progress.total > 0 {
                        Text("\(progress.done) / \(progress.total)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(phaseText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Cancel button.
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Cancel"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(String(localized: "Tap to see details"))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Internal for tests (issue #14).
    var iconName: String {
        switch progress.phase {
        case .downloading: return "arrow.down.circle.fill"
        case .extracting: return "doc.zipper"
        case .savingToPhotos: return "photo.circle.fill"
        }
    }

    /// Internal for tests (issue #14).
    var phaseText: String {
        switch progress.phase {
        case .downloading: return String(localized: "Downloading…")
        case .extracting: return String(localized: "Extracting…")
        case .savingToPhotos: return String(localized: "Saving to Photos…")
        }
    }

    /// Internal for tests (issue #14).
    var accessibilityText: String {
        let base = progress.title ?? String(localized: "Downloading…")
        let phase = phaseText
        if progress.total > 0 {
            return "\(base), \(phase), \(progress.done) / \(progress.total)"
        }
        return "\(base), \(phase)"
    }
}

#Preview {
    VStack(spacing: 0) {
        DownloadProgressBanner(
            progress: .init(phase: .savingToPhotos, done: 12, total: 27, title: "Summer 2025"),
            onTap: {},
            onCancel: {}
        )
        Spacer()
    }
    .background(Color(.systemBackground))
}
