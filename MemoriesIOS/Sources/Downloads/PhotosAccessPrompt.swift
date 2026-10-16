import Photos
import UIKit

/// Asks for full access to the photo library before saving downloads, and explains why first:
/// the iOS prompt alone does not say what the access is for.
@MainActor
enum PhotosAccessPrompt {
    /// Full or limited access after the explanation and the iOS prompt; `false` if refused.
    static func requestAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            guard await explain() else { return false }
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return status == .authorized || status == .limited
        default:
            await showDenied()
            return false
        }
    }

    /// Full access (not limited): needed to create albums.
    static var hasFullAccess: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    private static func explain() async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: String(localized: "Save to Photos"),
                message: String(localized: """
                    Memories saves your downloads to your photo library. Full access lets it skip the \
                    photos you already have, so nothing is duplicated, and recreate your albums.
                    """),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Not now"), style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: String(localized: "Continue"), style: .default) { _ in
                continuation.resume(returning: true)
            })
            guard present(alert) else { return continuation.resume(returning: false) }
        }
    }

    private static func showDenied() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(
                title: String(localized: "No access to Photos"),
                message: String(localized: "To save your downloads to Photos, allow Memories to access your photo library in Settings."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume()
            })
            alert.addAction(UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                continuation.resume()
            })
            guard present(alert) else { return continuation.resume() }
        }
    }

    /// Presents over the topmost screen; `false` if there is none.
    private static func present(_ controller: UIViewController) -> Bool {
        guard let top = SharePresenter.topViewController() else {
            Log.nativex.error("No screen to present the Photos access explanation")
            return false
        }
        top.present(controller, animated: true)
        return true
    }
}
