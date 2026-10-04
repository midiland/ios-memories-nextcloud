import Photos

/// When to open the frontend's device setup (`/nxsetup`) instead of the timeline, like Android
/// does after signing in: it offers device photos, and thus the iOS permission prompt.
enum DeviceSetupRule {
    /// Once per install, only while the user has neither opted in nor answered the iOS prompt.
    static func shouldOffer(alreadyOffered: Bool, isEnabled: Bool, status: PHAuthorizationStatus) -> Bool {
        !alreadyOffered && !isEnabled && status == .notDetermined
    }
}
