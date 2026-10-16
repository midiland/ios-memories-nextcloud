import Foundation
import UniformTypeIdentifiers

/// A downloaded photo or video, ready to be saved to Photos.
struct MediaFile: Equatable {
    let url: URL
    let isVideo: Bool

    /// `nil` when the file is neither a photo nor a video (judged by its extension).
    init?(url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) {
            isVideo = false
        } else if type.conforms(to: .movie) {
            isVideo = true
        } else {
            return nil
        }
        self.url = url
    }
}
