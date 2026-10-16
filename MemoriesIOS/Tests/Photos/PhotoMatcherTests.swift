import XCTest
@testable import Memories

final class PhotoMatcherTests: XCTestCase {
    /// iPhone photo taken at 2026-10-01 00:30 in Paris (UTC+2).
    private let epoch = 1_790_807_400
    private let offset = 7_200

    private func local(
        _ id: String, epoch: Int? = nil, w: Int = 4032, h: Int = 3024,
        isVideo: Bool = false, size: Int64? = nil, name: String? = nil
    ) -> PhotoMatcher.Candidate {
        let e = epoch ?? self.epoch
        return PhotoMatcher.Candidate(
            id: id, epoch: e, wallClockEpoch: e + offset, width: w, height: h, isVideo: isVideo,
            auid: size.map { PhotoIDs.auid(epoch: e, size: $0) },
            buid: name.flatMap { name in size.map { PhotoIDs.buid(basename: name, size: $0) } }
        )
    }

    private func server(
        _ fileid: Int64, epoch: Int? = nil, w: Int = 4032, h: Int = 3024, size: Int64 = 1_000,
        name: String = "IMG_0001.JPG", buid: String? = nil, isVideo: Bool = false
    ) -> ServerPhoto {
        ServerPhoto(fileid: fileid, dayid: 20_727, epoch: epoch ?? self.epoch, w: w, h: h, size: size,
                    basename: name, buid: buid, isVideo: isVideo)
    }

    func testHEICUploadedUnchangedMatchesByAuid() {
        let result = PhotoMatcher.match([local("a", size: 2_000_000)], against: [server(1, size: 2_000_000, name: "IMG_0001.HEIC")])
        XCTAssertEqual(result.matched, ["a"])
        XCTAssertEqual(result.byIdentifier, 1)
    }

    func testSameNameAndSizeMatchesByBuidEvenWithAnotherDate() {
        let buid = PhotoIDs.buid(basename: "IMG_0001.HEIC", size: 2_000_000)
        let photo = server(1, epoch: 1, w: 0, h: 0, size: 2_000_000, name: "IMG_0001.HEIC", buid: buid)
        let result = PhotoMatcher.match([local("a", size: 2_000_000, name: "IMG_0001.HEIC")], against: [photo])
        XCTAssertEqual(result.matched, ["a"])
    }

    func testConvertedAndRenamedJPEGMatchesByFingerprint() {
        // Same instant and dimensions, different size and name: HEIC → JPEG by the Nextcloud app.
        let photo = server(1, size: 3_500_000, name: "Photo 2026-10-01 00-30-00.jpg")
        let result = PhotoMatcher.match([local("a", size: 2_000_000, name: "IMG_0001.HEIC")], against: [photo])
        XCTAssertEqual(result.matched, ["a"])
        XCTAssertEqual(result.byFingerprint, 1)
    }

    func testRotatedOrResizedCopyMatches() {
        XCTAssertEqual(PhotoMatcher.match([local("a")], against: [server(1, w: 3024, h: 4032)]).matched, ["a"])
        XCTAssertEqual(PhotoMatcher.match([local("a")], against: [server(1, w: 2016, h: 1512)]).matched, ["a"])
    }

    func testServerDateWithoutTimezoneMatchesTheWallClock() {
        // EXIF date without offset: the server read 00:30 as UTC.
        XCTAssertEqual(PhotoMatcher.match([local("a")], against: [server(1, epoch: epoch + offset)]).matched, ["a"])
    }

    func testOneSecondRoundingIsTolerated() {
        XCTAssertEqual(PhotoMatcher.match([local("a")], against: [server(1, epoch: epoch + 1)]).matched, ["a"])
        XCTAssertTrue(PhotoMatcher.match([local("a")], against: [server(1, epoch: epoch + 2)]).matched.isEmpty)
    }

    func testDifferentPicturesDoNotMatch() {
        let others = [
            server(1, epoch: epoch + 60),                 // another minute
            server(2, w: 3024, h: 3024),                  // square crop
            server(3, isVideo: true),                     // a video at the same second
            server(4, epoch: epoch + offset * 2),         // not the wall clock
        ]
        XCTAssertTrue(PhotoMatcher.match([local("a")], against: others).matched.isEmpty)
    }

    func testUnknownDimensionsNeverMatchByFingerprint() {
        XCTAssertTrue(PhotoMatcher.match([local("a", w: 0, h: 0)], against: [server(1)]).matched.isEmpty)
        XCTAssertTrue(PhotoMatcher.match([local("a")], against: [server(1, w: 0, h: 0)]).matched.isEmpty)
    }

    func testBurstMatchesOneToOne() {
        // Three device photos in the same second, only two on the server: one stays device-only.
        let locals = [local("a"), local("b"), local("c")]
        let result = PhotoMatcher.match(locals, against: [server(1), server(2)])
        XCTAssertEqual(result.matched.count, 2)
        XCTAssertEqual(result.byFingerprint, 2)
    }

    func testIdentifierMatchIsNotReusedByAFingerprint() {
        // "a" is the server photo uploaded as is; "b" (same second) must not claim it too.
        let a = local("a", size: 2_000_000)
        let result = PhotoMatcher.match([a, local("b")], against: [server(1, size: 2_000_000)])
        XCTAssertEqual(result.matched, ["a"])
    }

    func testPrefersExactDimensions() {
        // Two server photos at the same second: the resized one must not steal the exact match.
        let locals = [local("a"), local("b", w: 1920, h: 1440)]
        let photos = [server(1, w: 1920, h: 1440), server(2)]
        XCTAssertEqual(PhotoMatcher.match(locals, against: photos).matched, ["a", "b"])
    }

    // MARK: - Server side (downloads saved to Photos)

    func testReportsWhichServerPhotosHaveADeviceCopy() {
        let locals = [local("a", size: 2_000_000), local("b", epoch: epoch + 60)]
        let photos = [server(1, size: 2_000_000), server(2, epoch: epoch + 60, size: 5), server(3, epoch: epoch + 3_600)]
        XCTAssertEqual(PhotoMatcher.match(locals, against: photos).matchedServer, [1, 2])
    }

    func testBurstReportsOnlyTheClaimedServerPhotos() {
        // One device photo, two server photos in the same second: only one is already on the device.
        XCTAssertEqual(PhotoMatcher.match([local("a")], against: [server(1), server(2)]).matchedServer.count, 1)
    }
}
