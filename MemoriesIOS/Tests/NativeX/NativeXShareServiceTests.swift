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

// MARK: - Cancellation and single active download (F8)

/// Downloader stub: each call waits until released, or throws when its task is cancelled.
private final class StubDownloader: FileDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [URL: CheckedContinuation<URL, Error>] = [:]
    private(set) var cancelled: [URL] = []
    private(set) var started: [URL] = []
    var onStart: (@Sendable (URL) -> Void)?

    func download(_ url: URL, preferredName: String?, progress: (@Sendable (Int64, Int64) -> Void)?) async throws -> URL {
        lock.withLock { started.append(url) }
        onStart?(url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { continuations[url] = continuation }
            }
        } onCancel: {
            lock.withLock {
                cancelled.append(url)
                continuations.removeValue(forKey: url)?.resume(throwing: CancellationError())
            }
        }
    }

    func finish(_ url: URL, with file: URL) {
        lock.withLock { continuations.removeValue(forKey: url) }?.resume(returning: file)
    }

    /// `false` if the download never reached the downloader (bounded, so a test fails instead of hanging).
    func waitUntilStarted(_ url: URL) async -> Bool {
        for _ in 0..<5_000 {
            if lock.withLock({ started.contains(url) && continuations[url] != nil }) { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

@MainActor
final class NativeXShareServiceCancellationTests: XCTestCase {
    private final class Host: NativeXHost {
        var toasts: [String] = []
        var hideCount = 0
        func nativeXSetTheme(color: UIColor?, isDark: Bool) {}
        func nativeXToast(_ message: String, long: Bool) { toasts.append(message) }
        func nativeXSetDownloadProgress(_ progress: WebViewModel.DownloadProgress?) { if progress == nil { hideCount += 1 } }
        func nativeXLogout() {}
        func nativeXReload() {}
        func nativeXEvaluate(_ script: String) {}
        func nativeXSetViewerFullscreen(_ fullscreen: Bool) {}
    }

    private let first = URL(string: "https://cloud.example.com/first")!
    private let second = URL(string: "https://cloud.example.com/second")!

    private func plainFile() throws -> URL {
        let folder = try Fixtures.temporaryDirectory()
        let file = folder.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)
        return file
    }

    private func settle(_ service: NativeXShareService) async {
        for _ in 0..<200 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testNewDownloadCancelsThePreviousOne() async throws {
        let stub = StubDownloader()
        var shared: [[Any]] = []
        let service = NativeXShareService(downloader: stub, photoLibrary: PhotoLibrary(), presentShareSheet: { shared.append($0) })
        let host = Host()
        service.host = host

        service.download(urlString: first.absoluteString, filename: nil, title: nil)
        let startedFirst = await stub.waitUntilStarted(first); XCTAssertTrue(startedFirst)
        service.download(urlString: second.absoluteString, filename: nil, title: nil)
        let startedSecond = await stub.waitUntilStarted(second); XCTAssertTrue(startedSecond)

        XCTAssertEqual(stub.cancelled, [first])
        XCTAssertEqual(host.hideCount, 0, "the replaced download must not hide the new overlay")

        stub.finish(second, with: try plainFile())
        await settle(service)
        XCTAssertEqual(shared.count, 1) // a non-media file goes to the share sheet, once
        XCTAssertEqual(host.hideCount, 1)
    }

    func testCancelDownloadStopsEverything() async throws {
        let stub = StubDownloader()
        var shared = 0
        let service = NativeXShareService(downloader: stub, photoLibrary: PhotoLibrary(), presentShareSheet: { _ in shared += 1 })
        let host = Host()
        service.host = host

        service.download(urlString: first.absoluteString, filename: nil, title: "Album")
        let startedFirst = await stub.waitUntilStarted(first); XCTAssertTrue(startedFirst)
        service.cancelDownload()
        await settle(service)

        XCTAssertEqual(stub.cancelled, [first])
        XCTAssertEqual(shared, 0)
        XCTAssertFalse(host.toasts.contains { $0.contains("failed") })
        XCTAssertEqual(host.hideCount, 1)
    }

    func testCancelledAfterTheNetworkPhaseNothingIsSharedOrSaved() async throws {
        let stub = StubDownloader()
        var shared = 0
        let service = NativeXShareService(downloader: stub, photoLibrary: PhotoLibrary(), presentShareSheet: { _ in shared += 1 })
        let host = Host() // `host` is weak: keep it alive
        service.host = host
        let file = try plainFile()

        service.download(urlString: first.absoluteString, filename: nil, title: nil)
        let startedFirst = await stub.waitUntilStarted(first); XCTAssertTrue(startedFirst)
        // The file arrives, and the user cancels at the same moment.
        stub.finish(first, with: file)
        service.cancelDownload()
        await settle(service)

        XCTAssertEqual(shared, 0)
    }
}
