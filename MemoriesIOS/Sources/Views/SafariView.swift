import SafariServices
import SwiftUI

/// `SFSafariViewController` for the Nextcloud login page.
///
/// Chosen over `ASWebAuthenticationSession`: Login Flow v2 does not redirect to any
/// callback scheme, so login completion is detected by polling. The sheet is closed
/// by `SessionStore` as soon as polling succeeds; "Done" closes the sheet and cancels the login.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .cancel
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
