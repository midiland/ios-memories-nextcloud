import Foundation

/// Finds which device photos already exist on the server (pure logic, unit tested).
///
/// 1. **Identifiers**: same `auid` (capture instant + file size) or same `buid` (name + size) as a
///    server photo — the file was uploaded unchanged (e.g. original HEIC).
/// 2. **Fingerprint**: same media type, same capture second and same aspect ratio — survives the
///    HEIC → JPEG conversion and the renaming done by the Nextcloud app. The server instant may also
///    be the wall-clock time read as UTC (EXIF date without timezone). Each server photo matches at
///    most one device photo, so a burst of N device photos never hides more than N server copies.
enum PhotoMatcher {
    /// A device photo, as seen by the matcher.
    struct Candidate: Equatable {
        let id: String
        let epoch: Int
        /// Capture wall-clock time read as UTC (see `PhotoIDs.wallClockEpoch`).
        let wallClockEpoch: Int
        let width: Int
        let height: Int
        let isVideo: Bool
        let auid: String?
        let buid: String?
    }

    struct Result: Equatable {
        /// IDs of the device photos that have a server copy.
        var matched: Set<String> = []
        var byIdentifier = 0
        var byFingerprint = 0
    }

    /// Capture instants are compared to the second; allow one second for rounding differences.
    static let epochTolerance = 1
    /// Relative aspect ratio difference still considered the same picture (resized copies).
    static let aspectTolerance = 0.01

    static func match(_ candidates: [Candidate], against server: [ServerPhoto]) -> Result {
        var result = Result()
        let auids = Set(server.map(\.auid))
        let buids = Set(server.compactMap(\.buid))

        var remaining: [Candidate] = []
        for candidate in candidates {
            if candidate.auid.map(auids.contains) == true || candidate.buid.map(buids.contains) == true {
                result.matched.insert(candidate.id)
                result.byIdentifier += 1
            } else {
                remaining.append(candidate)
            }
        }

        // Server photos already claimed by an identifier match are not available for fingerprints.
        var available = server.filter { photo in
            !candidates.contains { $0.auid == photo.auid || ($0.buid != nil && $0.buid == photo.buid) }
        }
        for candidate in remaining.sorted(by: { $0.epoch < $1.epoch }) {
            guard let index = bestMatch(for: candidate, in: available) else { continue }
            available.remove(at: index)
            result.matched.insert(candidate.id)
            result.byFingerprint += 1
        }
        return result
    }

    /// Index of the best fingerprint match: exact instant before wall-clock instant,
    /// exact dimensions before same aspect ratio.
    private static func bestMatch(for candidate: Candidate, in photos: [ServerPhoto]) -> Int? {
        var best: (index: Int, score: Int)?
        for (index, photo) in photos.enumerated() where photo.isVideo == candidate.isVideo {
            let exactTime = abs(photo.epoch - candidate.epoch) <= epochTolerance
            let wallTime = abs(photo.epoch - candidate.wallClockEpoch) <= epochTolerance
            guard exactTime || wallTime, sameAspect(candidate, photo) else { continue }
            let score = (exactTime ? 2 : 0) + (sameSize(candidate, photo) ? 1 : 0)
            if best == nil || score > best!.score { best = (index, score) }
        }
        return best?.index
    }

    /// Same dimensions, in either orientation.
    private static func sameSize(_ candidate: Candidate, _ photo: ServerPhoto) -> Bool {
        (candidate.width == photo.w && candidate.height == photo.h)
            || (candidate.width == photo.h && candidate.height == photo.w)
    }

    /// Same aspect ratio, in either orientation. Unknown dimensions on either side never match.
    private static func sameAspect(_ candidate: Candidate, _ photo: ServerPhoto) -> Bool {
        guard candidate.width > 0, candidate.height > 0, photo.w > 0, photo.h > 0 else { return false }
        let local = ratio(candidate.width, candidate.height)
        let remote = ratio(photo.w, photo.h)
        return abs(local - remote) / remote <= aspectTolerance
    }

    /// Long edge over short edge (orientation-independent).
    private static func ratio(_ a: Int, _ b: Int) -> Double {
        Double(max(a, b)) / Double(min(a, b))
    }
}
