import Photos
import UIKit

/// Renders device photos as JPEG for the web view (`/image/preview`, `/image/full`), like
/// `ImageService.kt`. HEIC and other formats are converted; iCloud originals are downloaded if needed.
struct LocalImageRenderer: Sendable {
    /// Default thumbnail box when the frontend gives no size.
    static let defaultPreviewSize = 512
    static let jpegQuality: CGFloat = 0.85

    /// Thumbnail fitted into `width` × `height` (points = pixels here).
    func preview(_ asset: PHAsset, width: Int?, height: Int?) async -> Data? {
        let w = width.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultPreviewSize
        let h = height.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultPreviewSize
        return await jpeg(asset, targetSize: CGSize(width: w, height: h))
    }

    /// Full image, downscaled (never upscaled) so its long edge fits `longEdge`.
    func full(_ asset: PHAsset, longEdge: Int?) async -> Data? {
        guard let longEdge, longEdge > 0, longEdge < max(asset.pixelWidth, asset.pixelHeight) else {
            return await jpeg(asset, targetSize: PHImageManagerMaximumSize)
        }
        return await jpeg(asset, targetSize: CGSize(width: longEdge, height: longEdge))
    }

    private func jpeg(_ asset: PHAsset, targetSize: CGSize) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // a single callback
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true // originals stored in iCloud
        options.version = .current // with the user's edits, as shown in Photos

        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return image?.jpegData(compressionQuality: Self.jpegQuality)
    }
}
