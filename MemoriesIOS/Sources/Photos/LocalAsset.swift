import Foundation

/// A photo of the device library (PhotoKit metadata only, no image data).
struct LocalAsset: Equatable, Sendable {
    let localIdentifier: String
    let creationDate: Date
    let modificationDate: Date?
    /// Pixel dimensions, as displayed.
    let width: Int
    let height: Int
    let isVideo: Bool

    /// Numeric ID shown to the frontend (`fileid`).
    var fileId: Int64 { PhotoIDs.fileId(localIdentifier: localIdentifier) }
    var epoch: Int { PhotoIDs.epoch(creationDate) }

    func dayId(in timeZone: TimeZone) -> Int { PhotoIDs.dayId(creationDate, in: timeZone) }
}

/// Original file of an asset (`PHAssetResource`): needed for `auid`/`buid`.
struct LocalResource: Equatable, Sendable {
    let basename: String
    /// `nil` when PhotoKit does not report it.
    let size: Int64?
    let mimetype: String
}
