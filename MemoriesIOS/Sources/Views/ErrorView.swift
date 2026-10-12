import SwiftUI

/// Generic error screen with "Retry" and "Log out" buttons.
struct ErrorView: View {
    let error: AppError
    let retry: () -> Void
    let logout: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
            Button("Log out", role: .destructive, action: logout)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var iconName: String {
        switch error {
        case .serverUnreachable: return "wifi.exclamationmark"
        case .noSignedManifest: return "lock.shield"
        case .memoriesNotInstalled, .serverTooOld: return "puzzlepiece.extension"
        case .notAuthenticated: return "person.crop.circle.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
}
