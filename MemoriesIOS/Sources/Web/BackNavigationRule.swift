import Foundation

/// Quand afficher le bouton retour natif.
///
/// En mode natif, le frontend masque sa barre de navigation hors des onglets principaux
/// (`showNavigation` dans `App.vue`) et compte sur le bouton « retour » d'Android pour sortir
/// de pages comme « Ce jour-là », Favoris, Vidéos, Carte ou Dossiers. iOS n'a pas de bouton
/// système : on affiche le nôtre sur ces pages uniquement.
enum BackNavigationRule {
    /// Routes de l'app (après `…/apps/memories`) où la barre de navigation est visible.
    private static let mainRoutes: Set<String> = ["", "/explore", "/albums"]

    /// Routes dont l'en-tête web a déjà sa propre flèche retour (`*TopMatter.vue`).
    private static let routesWithOwnBack = ["/albums/", "/places", "/tags", "/recognize", "/facerecognition"]

    static func showsBackButton(url: URL?, canGoBack: Bool, webRoot: String) -> Bool {
        guard canGoBack, let url else { return false }
        // Fragment = visionneuse, barre latérale ou fenêtre ouverte : elles ont leur bouton fermer.
        if let fragment = url.fragment, !fragment.isEmpty { return false }

        var route = url.path
        for prefix in [webRoot + "/index.php/apps/memories", webRoot + "/apps/memories"] where route.hasPrefix(prefix) {
            route.removeFirst(prefix.count)
            break
        }
        while route.hasSuffix("/") { route.removeLast() }

        if mainRoutes.contains(route) { return false }
        if routesWithOwnBack.contains(where: { route == $0 || route.hasPrefix($0) }) { return false }
        return true
    }
}
