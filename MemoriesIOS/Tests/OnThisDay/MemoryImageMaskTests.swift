import CoreImage
import XCTest
@testable import Memories

final class MemoryImageMaskTests: XCTestCase {
    /// Gray image whose pixels are written directly as bytes (no color-profile conversion,
    /// unlike `setFillColor(CGColor(gray:))` which gamma-corrects).
    private func grayImage(_ levels: [UInt8], width: Int, height: Int) -> UIImage {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        for i in 0..<(width * height) { buf[i] = levels[i] }
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: buf, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return UIImage(cgImage: ctx.makeImage()!)
    }

    /// Solid gray `size`x`size` image at the given 8-bit level.
    private func solidGray(_ level: UInt8, size: Int = 8) -> UIImage {
        grayImage(Array(repeating: level, count: size * size), width: size, height: size)
    }

    /// Image whose left half is black and right half is white.
    private func splitImage(size: Int = 8) -> UIImage {
        var levels = [UInt8]()
        for _ in 0..<size {
            levels += Array(repeating: 0, count: size / 2) + Array(repeating: 255, count: size / 2)
        }
        return grayImage(levels, width: size, height: size)
    }

    /// Raw RGBA bytes of the image's data provider (noneSkipLast: R, G, B, A per pixel).
    private func pixels(of image: UIImage) -> [UInt8] {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data as CFData? else { return [] }
        return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
    }

    func testSolidGrayMaskIsWhiteWithLuminanceAsAlpha() {
        let mask = MemoryImageMask.luminanceMask(of: solidGray(128))
        let px = pixels(of: mask)
        XCTAssertEqual(px.count, 8 * 8 * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            // Premultiplied white: stored R == G == B == alpha, and alpha is the gray level.
            XCTAssertEqual(px[i], px[i + 3], "R must equal alpha (white premultiplied)")
            XCTAssertEqual(px[i + 1], px[i + 3], "G must equal alpha (white premultiplied)")
            XCTAssertEqual(px[i + 2], px[i + 3], "B must equal alpha (white premultiplied)")
            XCTAssertEqual(px[i + 3], 128, "alpha must be the luminance")
        }
    }

    func testSplitMaskKeepsBothLuminanceLevels() {
        let mask = MemoryImageMask.luminanceMask(of: splitImage())
        let px = pixels(of: mask)
        var alphas = Set<UInt8>()
        for i in stride(from: 0, to: px.count, by: 4) {
            XCTAssertEqual(px[i], px[i + 3])
            XCTAssertEqual(px[i + 1], px[i + 3])
            XCTAssertEqual(px[i + 2], px[i + 3])
            alphas.insert(px[i + 3])
        }
        XCTAssertEqual(alphas, [0, 255])
    }

    func testMaskIsCachedPerImage() {
        let image = solidGray(200)
        XCTAssertTrue(MemoryImageMask.luminanceMask(of: image) === MemoryImageMask.luminanceMask(of: image))
    }

    func testImageWithoutCGImageIsReturnedUnchanged() {
        // A CIImage-backed UIImage has no cgImage: the mask falls back to the original.
        let ci = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = UIImage(ciImage: ci)
        XCTAssertNil(image.cgImage)
        XCTAssertTrue(MemoryImageMask.luminanceMask(of: image) === image)
    }
}
