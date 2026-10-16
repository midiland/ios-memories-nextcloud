import Foundation

/// Finds which downloaded photos are already in the device library, with the same rules as the
/// timeline (`PhotoMatcher`: identifiers, then capture second + aspect ratio). Needs read access:
/// with limited access only the photos shared with the app are seen.
struct DuplicateFinder {
    let library: PhotoLibrary
    var timeZone: TimeZone = .current

    struct Result {
        /// Indices (in the input list) of the files already in the library.
        var duplicates: Set<Int> = []
        /// Device photos matching them (added to the album instead of a second copy).
        var deviceCopies: Set<String> = []
    }

    func find(in media: [MediaFile]) async -> Result {
        var downloaded: [ServerPhoto] = []
        for (index, file) in media.enumerated() {
            if let photo = await MediaMetadata.serverPhoto(for: file, id: Int64(index)) { downloaded.append(photo) }
        }
        guard let first = downloaded.map(\.epoch).min(), let last = downloaded.map(\.epoch).max() else { return Result() }

        // The server epoch may be a wall-clock time read as UTC: widen by the largest UTC offsets.
        let margin: TimeInterval = 15 * 3_600
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: TimeInterval(first) - margin),
            end: Date(timeIntervalSince1970: TimeInterval(last) + margin)
        )
        let assets = library.assets(createdIn: interval)
        let resources = library.resources(for: assets.map(\.localIdentifier))
        let candidates = assets.map { PhotoMatcher.Candidate($0, resource: resources[$0.localIdentifier], timeZone: timeZone) }

        let match = PhotoMatcher.match(candidates, against: downloaded)
        return Result(duplicates: Set(match.matchedServer.map(Int.init)), deviceCopies: match.matched)
    }
}
