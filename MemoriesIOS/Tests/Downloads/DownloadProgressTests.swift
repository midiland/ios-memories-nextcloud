import XCTest
@testable import Memories

/// Tests for the album download progress (issue #14).
final class DownloadProgressTests: XCTestCase {
    // MARK: - DownloadProgress.fraction

    func testFractionIsZeroWhenTotalIsZero() {
        let progress = WebViewModel.DownloadProgress(phase: .downloading, done: 0, total: 0, title: nil)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testFractionIsZeroWhenTotalIsNegative() {
        let progress = WebViewModel.DownloadProgress(phase: .downloading, done: 5, total: -1, title: nil)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testFractionAtStart() {
        let progress = WebViewModel.DownloadProgress(phase: .downloading, done: 0, total: 100, title: nil)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testFractionAtMiddle() {
        let progress = WebViewModel.DownloadProgress(phase: .extracting, done: 50, total: 100, title: nil)
        XCTAssertEqual(progress.fraction, 0.5)
    }

    func testFractionAtEnd() {
        let progress = WebViewModel.DownloadProgress(phase: .savingToPhotos, done: 100, total: 100, title: nil)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testFractionIsCappedAtOne() {
        let progress = WebViewModel.DownloadProgress(phase: .downloading, done: 150, total: 100, title: nil)
        XCTAssertEqual(progress.fraction, 1)
    }

    func testFractionWithSmallNumbers() {
        let progress = WebViewModel.DownloadProgress(phase: .downloading, done: 1, total: 3, title: nil)
        XCTAssertEqual(progress.fraction, 1.0 / 3.0, accuracy: 0.001)
    }

    // MARK: - Equatable

    func testEquality() {
        let a = WebViewModel.DownloadProgress(phase: .downloading, done: 10, total: 100, title: "Album")
        let b = WebViewModel.DownloadProgress(phase: .downloading, done: 10, total: 100, title: "Album")
        let c = WebViewModel.DownloadProgress(phase: .extracting, done: 10, total: 100, title: "Album")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testPhaseEquality() {
        XCTAssertEqual(WebViewModel.DownloadProgress.Phase.downloading, .downloading)
        XCTAssertNotEqual(WebViewModel.DownloadProgress.Phase.downloading, .extracting)
        XCTAssertNotEqual(WebViewModel.DownloadProgress.Phase.extracting, .savingToPhotos)
    }

    // MARK: - Title

    func testTitleIsPreserved() {
        let withTitle = WebViewModel.DownloadProgress(phase: .downloading, done: 0, total: 0, title: "Summer 2025")
        XCTAssertEqual(withTitle.title, "Summer 2025")

        let withoutTitle = WebViewModel.DownloadProgress(phase: .downloading, done: 0, total: 0, title: nil)
        XCTAssertNil(withoutTitle.title)
    }
}
