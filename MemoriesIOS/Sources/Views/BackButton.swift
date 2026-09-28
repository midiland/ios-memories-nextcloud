import SwiftUI

/// Bouton retour flottant, en bas à gauche : la place de la barre de navigation web,
/// masquée sur les pages concernées (et loin des contrôles de zoom de la carte, en haut).
/// Le glissement depuis le bord gauche de l'écran fait la même chose.
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
        .accessibilityLabel("Retour")
    }
}
