import UIKit

/// Présente la feuille de partage iOS (`UIActivityViewController`) par-dessus l'écran courant.
/// Elle couvre aussi « Enregistrer l'image » et « Enregistrer dans Fichiers ».
@MainActor
enum SharePresenter {
    static func present(_ items: [Any]) {
        guard !items.isEmpty, let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad : la feuille est un popover, il lui faut une ancre.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    /// Contrôleur visible le plus haut dans la fenêtre active.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
