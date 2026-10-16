import Foundation

extension PhotoMatcher.Candidate {
    /// Candidate for a device photo. `auid`/`buid` come from its original file (`resource`):
    /// without a known size they cannot match the server's.
    init(_ asset: LocalAsset, resource: LocalResource?, timeZone: TimeZone) {
        let size = resource?.size
        self.init(
            id: asset.localIdentifier,
            epoch: asset.epoch,
            wallClockEpoch: PhotoIDs.wallClockEpoch(asset.creationDate, in: timeZone),
            width: asset.width,
            height: asset.height,
            isVideo: asset.isVideo,
            auid: size.map { PhotoIDs.auid(epoch: asset.epoch, size: $0) },
            buid: resource.flatMap { resource in size.map { PhotoIDs.buid(basename: resource.basename, size: $0) } }
        )
    }
}
