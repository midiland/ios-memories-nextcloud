import SwiftUI

/// Message temporaire façon toast Android, affiché en bas de l'écran.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .padding(.horizontal, 24)
            .padding(.bottom, 80)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
