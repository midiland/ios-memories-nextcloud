import AVFoundation
import Foundation
import ImageIO

/// Reads what deduplication needs from a downloaded file: capture instant, displayed size, file size.
/// The result is shaped like a server photo, so `PhotoMatcher` compares it with the device photos.
enum MediaMetadata {
    /// `nil` when the capture date is unknown: such a file is always saved.
    static func serverPhoto(for media: MediaFile, id: Int64) async -> ServerPhoto? {
        let size = (try? media.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let name = media.url.lastPathComponent
        let info = media.isVideo ? await videoInfo(media.url) : imageInfo(media.url)
        guard let info else { return nil }
        return ServerPhoto(
            fileid: id, dayid: 0, epoch: info.epoch, w: info.width, h: info.height, size: size,
            basename: name, buid: PhotoIDs.buid(basename: name, size: size), isVideo: media.isVideo
        )
    }

    private struct Info {
        let epoch: Int
        let width: Int
        let height: Int
    }

    private static func imageInfo(_ url: URL) -> Info? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
              let epoch = CaptureDate.epoch(exifDate: date, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        else { return nil }
        var width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Orientations 5–8 are rotated by 90°: Photos reports the displayed size.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        return Info(epoch: epoch, width: width, height: height)
    }

    private static func videoInfo(_ url: URL) async -> Info? {
        let asset = AVURLAsset(url: url)
        guard let item = try? await asset.load(.creationDate),
              let date = try? await item.load(.dateValue)
        else { return nil }
        var size = CGSize.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            size = natural.applying(transform)
        }
        return Info(epoch: PhotoIDs.epoch(date), width: Int(abs(size.width)), height: Int(abs(size.height)))
    }
}
