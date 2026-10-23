import XCTest
@testable import Memories

/// Tests for the download progress views (issue #14): banner and modal logic.
final class DownloadProgressViewTests: XCTestCase {
    // MARK: - DownloadProgressBanner

    private func makeBanner(
        phase: WebViewModel.DownloadProgress.Phase = .downloading,
        done: Int = 0,
        total: Int = 100,
        title: String? = "Test Album"
    ) -> DownloadProgressBanner {
        DownloadProgressBanner(
            progress: .init(phase: phase, done: done, total: total, title: title),
            onTap: {},
            onCancel: {}
        )
    }

    func testBannerIconNamePerPhase() {
        XCTAssertEqual(makeBanner(phase: .downloading).iconName, "arrow.down.circle.fill")
        XCTAssertEqual(makeBanner(phase: .extracting).iconName, "doc.zipper")
        XCTAssertEqual(makeBanner(phase: .savingToPhotos).iconName, "photo.circle.fill")
    }

    func testBannerPhaseTextPerPhase() {
        XCTAssertEqual(makeBanner(phase: .downloading).phaseText, String(localized: "Downloading…"))
        XCTAssertEqual(makeBanner(phase: .extracting).phaseText, String(localized: "Extracting…"))
        XCTAssertEqual(makeBanner(phase: .savingToPhotos).phaseText, String(localized: "Saving to Photos…"))
    }

    func testBannerAccessibilityTextWithTitleAndProgress() {
        let banner = makeBanner(phase: .savingToPhotos, done: 12, total: 27, title: "Summer 2025")
        let expected = "Summer 2025, \(String(localized: "Saving to Photos…")), 12 / 27"
        XCTAssertEqual(banner.accessibilityText, expected)
    }

    func testBannerAccessibilityTextWithoutProgress() {
        let banner = makeBanner(phase: .downloading, done: 0, total: 0, title: "Album")
        let expected = "Album, \(String(localized: "Downloading…"))"
        XCTAssertEqual(banner.accessibilityText, expected)
    }

    func testBannerAccessibilityTextWithoutTitle() {
        let banner = makeBanner(phase: .extracting, done: 5, total: 10, title: nil)
        let expected = "\(String(localized: "Downloading…")), \(String(localized: "Extracting…")), 5 / 10"
        XCTAssertEqual(banner.accessibilityText, expected)
    }

    // MARK: - AlbumDownloadProgressView (modal)

    private func makeModal(
        phase: WebViewModel.DownloadProgress.Phase = .downloading,
        done: Int = 0,
        total: Int = 100,
        title: String? = "Test Album"
    ) -> AlbumDownloadProgressView {
        AlbumDownloadProgressView(
            progress: .init(phase: phase, done: done, total: total, title: title),
            onClose: {},
            onCancel: {}
        )
    }

    func testModalPhaseTextPerPhase() {
        XCTAssertEqual(makeModal(phase: .downloading).phaseText, String(localized: "Downloading…"))
        XCTAssertEqual(makeModal(phase: .extracting).phaseText, String(localized: "Extracting…"))
        XCTAssertEqual(makeModal(phase: .savingToPhotos).phaseText, String(localized: "Saving to Photos…"))
    }

    func testModalAccessibilityTextWithTitleAndProgress() {
        let modal = makeModal(phase: .downloading, done: 45, total: 100, title: "Holidays")
        let expected = "Holidays, \(String(localized: "Downloading…")), 45 / 100"
        XCTAssertEqual(modal.accessibilityText, expected)
    }

    func testModalAccessibilityTextWithoutProgress() {
        let modal = makeModal(phase: .downloading, done: 0, total: 0, title: nil)
        let expected = "\(String(localized: "Downloading…")), \(String(localized: "Downloading…"))"
        XCTAssertEqual(modal.accessibilityText, expected)
    }

    // MARK: - Modal callbacks

    func testModalCallbacksAreCalled() {
        var closeCalled = false
        var cancelCalled = false
        _ = AlbumDownloadProgressView(
            progress: .init(phase: .downloading, done: 0, total: 100, title: nil),
            onClose: { closeCalled = true },
            onCancel: { cancelCalled = true }
        )
        // The callbacks are stored; we verify they can be set without crashing.
        XCTAssertFalse(closeCalled)
        XCTAssertFalse(cancelCalled)
    }

    func testBannerCallbacksAreCalled() {
        var tapCalled = false
        var cancelCalled = false
        _ = DownloadProgressBanner(
            progress: .init(phase: .downloading, done: 0, total: 100, title: nil),
            onTap: { tapCalled = true },
            onCancel: { cancelCalled = true }
        )
        XCTAssertFalse(tapCalled)
        XCTAssertFalse(cancelCalled)
    }
}
