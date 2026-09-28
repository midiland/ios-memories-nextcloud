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
            Button("Réessayer", action: retry)
                .buttonStyle(.borderedProminent)
            Button("Se déconnecter", role: .destructive, action: logout)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var iconName: String {
        switch error {
        case .serverUnreachable: return "wifi.exclamationmark"
        case .memoriesNotInstalled, .serverTooOld: return "puzzlepiece.extension"
        case .notAuthenticated: return "person.crop.circle.badge.exclamationmark"
        default: return "exclamationmark.triangle"
        }
    }
}
