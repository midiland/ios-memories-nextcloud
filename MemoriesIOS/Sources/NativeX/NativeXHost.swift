import UIKit

/// Ce que le pont NativeX demande à l'app hôte (implémenté par `WebViewModel`).
/// Le pont décode les messages JS, l'hôte agit sur l'UI et la session.
@MainActor
protocol NativeXHost: AnyObject {
    /// Compte courant (pour télécharger avec les bons identifiants).
    var credentials: Credentials { get }

    /// Couleur de thème de l'UI web (`nil` = couleur système), et si elle est sombre.
    func nativeXSetTheme(color: UIColor?, isDark: Bool)

    /// Message court affiché par-dessus la WebView.
    func nativeXToast(_ message: String, long: Bool)

    /// Déconnexion demandée depuis Paramètres > Compte dans l'UI web.
    func nativeXLogout()

    /// Recharge complète (réamorçage de la session + page Memories).
    func nativeXReload()
}
