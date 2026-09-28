import SwiftUI

/// Floating back button, bottom left: replaces the web navigation bar, which is
/// hidden on the relevant pages (and stays away from the map zoom controls at the top).
/// Swiping from the left edge of the screen does the same thing.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .foregroundStyle(.primary)
        .padding(.leading, 16)
        .padding(.bottom, 16)
        .accessibilityLabel("Back")
    }
}
