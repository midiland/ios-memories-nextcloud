import SafariServices
import SwiftUI

/// `SFSafariViewController` pour la page de login Nextcloud.
///
/// Choisi plutôt qu'`ASWebAuthenticationSession` : le Login Flow v2 ne redirige vers aucun
/// schéma de retour, la fin de connexion est détectée par polling. La feuille est fermée
/// par `SessionStore` dès que le polling aboutit ; « OK » ferme la feuille et annule le login.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .cancel
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
