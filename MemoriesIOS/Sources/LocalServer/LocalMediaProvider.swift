import Foundation

/// Device photos served by the local server as JPEG (`/image/preview/{fileid}`, `/image/full/{auid}`).
/// These URLs are loaded by `<img>` and the frontend's image worker, which the JS bridge cannot intercept.
protocol LocalMediaProvider: Sendable {
    func preview(fileId: Int64, width: Int?, height: Int?) async -> Data?
    func full(auid: String, longEdge: Int?) async -> Data?
}
