import Foundation
import UIKit

/// Turns a photo into a white mask whose alpha channel is its luminance, so that a tinted
/// (accented) widget can show the photo's shades in the accent color instead of a flat block
/// (issue #20). Shared with the widget target: it must stay free of app-only dependencies.
enum MemoryImageMask {
    private static let cache = NSCache<UIImage, UIImage>()

    /// White image whose alpha is the luminance of `image`; `image` itself when it has no
    /// `cgImage` (the system then falls back to its own rendering).
    static func luminanceMask(of image: UIImage) -> UIImage {
        if let cached = cache.object(forKey: image) { return cached }
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        let graySpace = CGColorSpaceCreateDeviceGray()
        guard let grayCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: graySpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        grayCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let grayData = grayCtx.data else { return image }
        let gray = grayData.bindMemory(to: UInt8.self, capacity: w * h)

        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { rgba.deallocate() }
        for i in 0..<(w * h) {
            // Premultiplied white: R == G == B == alpha == luminance.
            rgba[i * 4] = gray[i]
            rgba[i * 4 + 1] = gray[i]
            rgba[i * 4 + 2] = gray[i]
            rgba[i * 4 + 3] = gray[i]
        }
        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        guard let outCtx = CGContext(data: rgba, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: rgbSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let out = outCtx.makeImage() else { return image }
        let mask = UIImage(cgImage: out)
        cache.setObject(mask, forKey: image)
        return mask
    }
}
