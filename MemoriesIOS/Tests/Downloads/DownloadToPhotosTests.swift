import XCTest
@testable import Memories

final class DownloadToPhotosTests: XCTestCase {
    // MARK: - Capture date

    func testExifDateWithOffsetIsTheRealInstant() {
        // 2026-10-01 00:30 in Paris (UTC+2) = 2026-09-30 22:30 UTC.
        XCTAssertEqual(CaptureDate.epoch(exifDate: "2026:10:01 00:30:00", offset: "+02:00"), 1_790_807_400)
        XCTAssertEqual(CaptureDate.epoch(exifDate: "2026:10:01 00:30:00", offset: "-05:30"), 1_790_814_600 + 19_800)
    }

    func testExifDateWithoutOffsetIsTheWallClockReadAsUTC() {
        XCTAssertEqual(CaptureDate.epoch(exifDate: "2026:10:01 00:30:00", offset: nil), 1_790_814_600)
        XCTAssertEqual(CaptureDate.epoch(exifDate: "2026:10:01 00:30:00", offset: "garbage"), 1_790_814_600)
    }

    func testInvalidExifDate() {
        XCTAssertNil(CaptureDate.epoch(exifDate: "0000:00:00 00:00:00", offset: nil))
        XCTAssertNil(CaptureDate.epoch(exifDate: "", offset: nil))
    }

    // MARK: - Media type

    func testPhotosAndVideosAreMedia() {
        for name in ["IMG.HEIC", "a.jpg", "b.png", "c.dng"] {
            XCTAssertEqual(MediaFile(url: URL(fileURLWithPath: name))?.isVideo, false, name)
        }
        for name in ["IMG.MOV", "clip.mp4"] {
            XCTAssertEqual(MediaFile(url: URL(fileURLWithPath: name))?.isVideo, true, name)
        }
        for name in ["doc.pdf", "notes.txt", "album.zip", "noextension"] {
            XCTAssertNil(MediaFile(url: URL(fileURLWithPath: name)), name)
        }
    }

    // MARK: - Result message

    @MainActor
    func testResultMessages() {
        typealias R = PhotosSaver.Result
        XCTAssertEqual(NativeXShareService.message(for: R(saved: 12)), String(localized: "Saved to Photos (\(12))"))
        XCTAssertEqual(NativeXShareService.message(for: R(saved: 0, alreadyInPhotos: 3)), String(localized: "Already in Photos"))
        XCTAssertEqual(
            NativeXShareService.message(for: R(saved: 2, alreadyInPhotos: 3)),
            String(localized: "Saved to Photos (\(2)), already there: \(3)")
        )
        XCTAssertEqual(
            NativeXShareService.message(for: R(saved: 5, failed: 1)),
            String(localized: "\(1) files could not be saved to Photos")
        )
    }
}
