import UIKit

/// Presents the iOS share sheet (`UIActivityViewController`) over the current screen.
/// It also covers "Save Image" and "Save to Files".
@MainActor
enum SharePresenter {
    static func present(_ items: [Any]) {
        guard !items.isEmpty, let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad: the sheet is a popover and needs an anchor.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    /// Topmost visible view controller in the key window.
    static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
