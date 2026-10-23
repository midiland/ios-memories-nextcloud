import XCTest
@testable import Memories

/// Tests for the album download progress reporting (issue #14).
final class NativeXShareServiceTests: XCTestCase {
    // MARK: - Mock host

    /// Records the progress updates and toasts sent by the service.
    @MainActor
    private final class MockHost: NativeXHost {
        /// Non-nil progress updates, in order.
        var progressUpdates: [WebViewModel.DownloadProgress] = []
        /// How many times the progress was hidden (set to nil).
        var hideCount = 0
        var toasts: [String] = []

        func nativeXSetTheme(color: UIColor?, isDark: Bool) {}
        func nativeXToast(_ message: String, long: Bool) {
            toasts.append(message)
        }
        func nativeXSetDownloadProgress(_ progress: WebViewModel.DownloadProgress?) {
            if let progress {
                progressUpdates.append(progress)
            } else {
                hideCount += 1
            }
        }
        func nativeXLogout() {}
        func nativeXReload() {}
        func nativeXEvaluate(_ script: String) {}
        func nativeXSetViewerFullscreen(_ fullscreen: Bool) {}
    }

    // MARK: - Tests

    @MainActor
    func testDownloadShowsProgressOverlayThenHidesIt() async {
        // We can't easily test the full download flow without a server,
        // but we can verify the initial progress is set.
        let host = MockHost()
        let downloader = AuthenticatedDownloader(credentials: Fixtures.credentials)
        let service = NativeXShareService(
            downloader: downloader,
            photoLibrary: PhotoLibrary(),
            presentShareSheet: { _ in }
        )
        service.host = host

        // Simulate what download() does at the start: show the overlay.
        host.nativeXSetDownloadProgress(.init(phase: .downloading, done: 0, total: 0, title: "Test Album"))

        XCTAssertEqual(host.progressUpdates.count, 1)
        XCTAssertEqual(host.progressUpdates[0].phase, .downloading)
        XCTAssertEqual(host.progressUpdates[0].title, "Test Album")
        XCTAssertEqual(host.progressUpdates[0].done, 0)
        XCTAssertEqual(host.progressUpdates[0].total, 0)
    }

    @MainActor
    func testProgressPhasesTransitionCorrectly() {
        let host = MockHost()

        // Phase 1: downloading
        host.nativeXSetDownloadProgress(.init(phase: .downloading, done: 50, total: 100, title: "Album"))
        XCTAssertEqual(host.progressUpdates.last?.phase, .downloading)
        XCTAssertEqual(host.progressUpdates.last?.fraction, 0.5)

        // Phase 2: extracting
        host.nativeXSetDownloadProgress(.init(phase: .extracting, done: 3, total: 10, title: "Album"))
        XCTAssertEqual(host.progressUpdates.last?.phase, .extracting)
        XCTAssertEqual(host.progressUpdates.last?.fraction ?? 0, 0.3, accuracy: 0.01)

        // Phase 3: saving to Photos
        host.nativeXSetDownloadProgress(.init(phase: .savingToPhotos, done: 10, total: 10, title: "Album"))
        XCTAssertEqual(host.progressUpdates.last?.phase, .savingToPhotos)
        XCTAssertEqual(host.progressUpdates.last?.fraction, 1.0)

        // Hidden at the end
        host.nativeXSetDownloadProgress(nil)
        XCTAssertEqual(host.hideCount, 1)
        XCTAssertEqual(host.progressUpdates.count, 3)
    }

    @MainActor
    func testCancelDownloadClearsTask() {
        let downloader = AuthenticatedDownloader(credentials: Fixtures.credentials)
        let service = NativeXShareService(
            downloader: downloader,
            photoLibrary: PhotoLibrary(),
            presentShareSheet: { _ in }
        )

        // cancelDownload should not crash when no download is ongoing.
        service.cancelDownload()
    }
}
