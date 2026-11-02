import XCTest
@testable import Memories

/// Tests for the remote-wipe flow in `SessionStore` (issue #15).
///
/// Not `@MainActor`: `SessionStore` is `@MainActor`, so we hop to the main actor
/// explicitly with `await MainActor.run { }` to avoid deadlocking the test runner.
final class SessionStoreWipeTests: XCTestCase {
    /// One recorded wipe call (server + token).
    private struct WipeCall: Equatable {
        let server: ServerURL
        let token: String
    }

    /// Mock wipe checker: records calls and returns canned results.
    private final class MockWipeChecker: WipeChecker {
        var checkWipeResult: Result<Bool, Error> = .success(false)
        var checkWipeCalls: [WipeCall] = []
        var confirmWipeCalls: [WipeCall] = []
        var confirmWipeResult: Bool = true
        /// Runs when `confirmWipe` is called, to observe the state at that moment.
        var onConfirm: (@MainActor () -> Void)?

        func checkWipe(server: ServerURL, token: String) async throws -> Bool {
            checkWipeCalls.append(WipeCall(server: server, token: token))
            return try checkWipeResult.get()
        }

        func confirmWipe(server: ServerURL, token: String) async -> Bool {
            confirmWipeCalls.append(WipeCall(server: server, token: token))
            await onConfirm?()
            return confirmWipeResult
        }
    }

    /// The pending entry matching `Fixtures.credentials` (server + token only).
    private var pending: PendingWipe { PendingWipe(server: Fixtures.server, token: Fixtures.credentials.appPassword) }
    /// The call the mock must be called with.
    private var expectedCall: WipeCall { WipeCall(server: Fixtures.server, token: Fixtures.credentials.appPassword) }

    private var sessionEndCount = 0
    private var mockChecker: MockWipeChecker!
    private var appSupport: URL!
    private var caches: URL!
    private var temporary: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var credentialStore: CredentialStore!
    private var pendingWipeStore: PendingWipeStore!
    /// Mutable clock for the throttle tests.
    private var currentTime = Date()

    override func setUp() async throws {
        try await super.setUp()
        sessionEndCount = 0
        mockChecker = MockWipeChecker()
        appSupport = try Fixtures.temporaryDirectory()
        caches = try Fixtures.temporaryDirectory()
        temporary = try Fixtures.temporaryDirectory()
        suiteName = "fr.midiland.memories.tests.session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        credentialStore = CredentialStore(service: "fr.midiland.memories.tests.session.\(UUID().uuidString)")
        pendingWipeStore = PendingWipeStore(service: "fr.midiland.memories.tests.session.wipe.\(UUID().uuidString)")
        currentTime = Date()
    }

    override func tearDown() async throws {
        credentialStore.delete()
        pendingWipeStore.delete()
        try? FileManager.default.removeItem(at: appSupport)
        try? FileManager.default.removeItem(at: caches)
        try? FileManager.default.removeItem(at: temporary)
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    @MainActor
    private func makeStore(credentials: Credentials? = Fixtures.credentials) -> SessionStore {
        // Pre-seed the Keychain so the store starts logged in.
        if let credentials {
            try? credentialStore.save(credentials)
        }
        let wiper = DataWiper(
            appSupport: appSupport,
            caches: caches,
            temporary: temporary,
            defaults: defaults,
            defaultsDomain: suiteName,
            credentialStore: credentialStore
        )
        return SessionStore(
            onSessionEnd: { [weak self] in self?.sessionEndCount += 1 },
            wipeChecker: mockChecker,
            dataWiper: wiper,
            credentialStore: credentialStore,
            pendingWipeStore: pendingWipeStore,
            now: { [weak self] in self?.currentTime ?? Date() }
        )
    }

    /// Waits until `condition` is true, with a timeout. Yields to let async work run.
    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    // MARK: - sessionRevoked

    func testSessionRevokedChecksWipeBeforeTearingDown() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(false)

        await MainActor.run { store.sessionRevoked() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(mockChecker.checkWipeCalls, [expectedCall])
        XCTAssertEqual(sessionEndCount, 1)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .notAuthenticated)
        let phase = await MainActor.run { store.phase }
        XCTAssertEqual(phase, .loggedOut)
        XCTAssertTrue(mockChecker.confirmWipeCalls.isEmpty, "no wipe → no confirm")
    }

    func testSessionRevokedPerformsWipeWhenRequested() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = true

        let offline = appSupport.appendingPathComponent("offline", isDirectory: true)
        try FileManager.default.createDirectory(at: offline, withIntermediateDirectories: true)

        await MainActor.run { store.sessionRevoked() }
        await waitFor { self.mockChecker.confirmWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(mockChecker.checkWipeCalls, [expectedCall])
        XCTAssertEqual(mockChecker.confirmWipeCalls, [expectedCall])
        XCTAssertEqual(sessionEndCount, 1)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .remoteWipe)
        let phase = await MainActor.run { store.phase }
        XCTAssertEqual(phase, .loggedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: offline.path), "local data must be erased")
    }

    func testSessionRevokedSavesPendingAndEndsSessionOnNetworkError() async throws {
        // A 401 + a failing wipe check: the credentials are saved as pending and the
        // session ends (the user gets the login screen). The pending is resolved on
        // the next launch.
        let store = await makeStore()
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        await MainActor.run { store.sessionRevoked() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(sessionEndCount, 1, "session must end (user not stuck)")
        let phase = await MainActor.run { store.phase }
        XCTAssertEqual(phase, .loggedOut)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .notAuthenticated)
        XCTAssertEqual(pendingWipeStore.load(), pending, "pending must be saved for retry")
        XCTAssertTrue(mockChecker.confirmWipeCalls.isEmpty)
    }

    func testPendingIsSavedAndUILeftBeforeConfirmation() async throws {
        // At confirmation time the purge already ran: the pending entry must exist (the
        // Keychain credentials are gone) and the UI must already be on the login screen.
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        var pendingDuringConfirm: PendingWipe?
        var credentialsDuringConfirm: Credentials?
        var phaseDuringConfirm: SessionStore.Phase?
        mockChecker.onConfirm = { [self] in
            pendingDuringConfirm = pendingWipeStore.load()
            credentialsDuringConfirm = credentialStore.load()
            phaseDuringConfirm = store.phase
        }

        await MainActor.run { store.sessionRevoked() }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(pendingDuringConfirm, pending, "pending saved before the purge")
        XCTAssertNil(credentialsDuringConfirm, "Keychain credentials erased before the confirmation")
        XCTAssertEqual(phaseDuringConfirm, .loggedOut, "UI left before the purge")
        XCTAssertNil(pendingWipeStore.load(), "pending cleared after a successful confirmation")
    }

    func testWipeRunsOnlyOnceWhenDetectedTwice() async throws {
        // At startup the proactive check and the 401 handler can both see the same wipe.
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)

        await MainActor.run {
            store.sessionRevoked()
            store.checkForRemoteWipe()
        }
        await waitFor { self.sessionEndCount >= 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockChecker.confirmWipeCalls.count, 1, "the wipe must be confirmed once")
        XCTAssertEqual(sessionEndCount, 1, "the session must end once")
    }

    func testSessionRevokedSavesPendingWhenConfirmFails() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = false // confirmation fails

        await MainActor.run { store.sessionRevoked() }
        await waitFor { self.mockChecker.confirmWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(sessionEndCount, 1)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .remoteWipe)
        var expected = pending
        expected.attempts = 1
        XCTAssertEqual(pendingWipeStore.load(), expected, "pending must be saved (counted) for retry")
    }

    func testSessionRevokedWhenLoggedOutIsImmediate() async {
        let store = await makeStore(credentials: nil) // logged out
        await MainActor.run { store.sessionRevoked() }
        let count = await MainActor.run { sessionEndCount }
        XCTAssertEqual(count, 1)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .notAuthenticated)
        XCTAssertTrue(mockChecker.checkWipeCalls.isEmpty, "no credentials → no check")
    }

    // MARK: - Idempotence (point C)

    func testSessionRevokedIsIdempotent() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = true

        // Two calls in quick succession: only one revocation task runs.
        await MainActor.run {
            store.sessionRevoked()
            store.sessionRevoked()
        }
        await waitFor { self.sessionEndCount == 1 }

        // Only one check and one confirm: the second call was ignored.
        XCTAssertEqual(mockChecker.checkWipeCalls.count, 1, "second call must be ignored")
        XCTAssertEqual(mockChecker.confirmWipeCalls.count, 1)
    }

    // MARK: - checkForRemoteWipe

    func testCheckForRemoteWipeDoesNothingWhenNoWipe() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(false)

        await MainActor.run { store.checkForRemoteWipe() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }

        XCTAssertEqual(mockChecker.checkWipeCalls, [expectedCall])
        XCTAssertEqual(sessionEndCount, 0, "no wipe → session stays")
        let phase = await MainActor.run { store.phase }
        XCTAssertEqual(phase, .loggedIn(Fixtures.credentials))
        XCTAssertTrue(mockChecker.confirmWipeCalls.isEmpty)
    }

    func testCheckForRemoteWipePerformsWipeWhenRequested() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = true

        await MainActor.run { store.checkForRemoteWipe() }
        await waitFor { self.mockChecker.confirmWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        XCTAssertEqual(mockChecker.checkWipeCalls, [expectedCall])
        XCTAssertEqual(mockChecker.confirmWipeCalls, [expectedCall])
        XCTAssertEqual(sessionEndCount, 1)
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .remoteWipe)
    }

    func testCheckForRemoteWipeIgnoresNetworkError() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        await MainActor.run { store.checkForRemoteWipe() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await Task.yield()

        XCTAssertEqual(mockChecker.checkWipeCalls.count, 1)
        XCTAssertEqual(sessionEndCount, 0, "network error → keep the session")
        let error = await MainActor.run { store.loginError }
        XCTAssertNil(error)
    }

    func testCheckForRemoteWipeWhenLoggedOutDoesNothing() async {
        let store = await makeStore(credentials: nil)
        await MainActor.run { store.checkForRemoteWipe() }
        await Task.yield()
        XCTAssertTrue(mockChecker.checkWipeCalls.isEmpty)
    }

    // MARK: - Throttle (point I: injected clock)

    func testCheckForRemoteWipeIsThrottled() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(false)

        // First call: goes through.
        await MainActor.run { store.checkForRemoteWipe() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }

        // Second call immediately after: throttled (less than 60s).
        await MainActor.run { store.checkForRemoteWipe() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(mockChecker.checkWipeCalls.count, 1, "second call must be throttled")

        // Advance the clock by 61 seconds: the check goes through again.
        currentTime = currentTime.addingTimeInterval(61)
        await MainActor.run { store.checkForRemoteWipe() }
        await waitFor { self.mockChecker.checkWipeCalls.count == 2 }
    }

    // MARK: - Proactive check does not cancel revocation

    func testProactiveCheckDoesNotCancelRevocation() async throws {
        let store = await makeStore()
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = true

        await MainActor.run { store.sessionRevoked() }
        await MainActor.run { store.checkForRemoteWipe() }

        await waitFor { self.sessionEndCount == 1 }
        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .remoteWipe, "revocation must complete despite proactive check")
    }

    // MARK: - resolvePendingWipe (point B: resolved on next launch)

    func testResolvePendingWipePerformsWipeWhenStillRequested() async throws {
        // Simulate a previous launch that saved a pending entry (401 + network error).
        try pendingWipeStore.save(pending)
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = true

        // A new SessionStore resolves the pending entry on init.
        let store = await makeStore(credentials: nil) // not logged in
        await waitFor { self.mockChecker.confirmWipeCalls.count == 1 }
        await waitFor { self.sessionEndCount == 1 }

        let error = await MainActor.run { store.loginError }
        XCTAssertEqual(error, .remoteWipe)
        XCTAssertNil(pendingWipeStore.load(), "pending must be cleared after successful wipe")
    }

    func testResolvePendingWipeDeletesWhenNoWipeRequested() async throws {
        // Simulate a pending entry for a plain revocation (no wipe).
        try pendingWipeStore.save(pending)
        mockChecker.checkWipeResult = .success(false) // no wipe

        let store = await makeStore(credentials: nil)
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        // Give the task a chance to finish.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(pendingWipeStore.load(), "pending must be deleted when no wipe is requested")
        XCTAssertEqual(sessionEndCount, 0, "no session to end (was not logged in)")
        let phase = await MainActor.run { store.phase }
        XCTAssertEqual(phase, .loggedOut)
    }

    func testResolvePendingWipeKeepsEntryOnNetworkError() async throws {
        try pendingWipeStore.save(pending)
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        let store = await makeStore(credentials: nil) // retained: the resolving task is [weak self]
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotNil(pendingWipeStore.load(), "pending must be kept on network error")
        _ = store
    }

    // MARK: - Pending entry: only server + token, bounded retries (issue #15 review)

    func testPendingEntryStoresOnlyServerAndToken() async throws {
        try pendingWipeStore.save(pending)
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        let store = await makeStore(credentials: nil) // retained: the resolving task is [weak self]
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await waitFor { self.pendingWipeStore.load() != nil }

        let loaded = try XCTUnwrap(pendingWipeStore.load())
        XCTAssertEqual(loaded.server, Fixtures.server)
        XCTAssertEqual(loaded.token, Fixtures.credentials.appPassword)
        let json = String(data: try JSONEncoder().encode(loaded), encoding: .utf8)!
        XCTAssertFalse(json.contains(Fixtures.credentials.loginName), "login name must not be persisted")
        _ = store
    }

    func testResolvePendingWipeCountsFailedAttempt() async throws {
        try pendingWipeStore.save(pending)
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        let store = await makeStore(credentials: nil) // retained: the resolving task is [weak self]
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await waitFor { (self.pendingWipeStore.load()?.attempts ?? 0) == 1 }

        XCTAssertEqual(pendingWipeStore.load()?.attempts, 1, "a failed check must be counted")
        _ = store
    }

    func testResolvePendingWipeDropsEntryAfterMaxAttempts() async throws {
        var almostThere = pending
        almostThere.attempts = PendingWipeStore.maxAttempts - 1
        try pendingWipeStore.save(almostThere)
        mockChecker.checkWipeResult = .failure(AppError.serverUnreachable("offline"))

        let store = await makeStore(credentials: nil) // retained: the resolving task is [weak self]
        await waitFor { self.mockChecker.checkWipeCalls.count == 1 }
        await waitFor { self.pendingWipeStore.load() == nil }

        XCTAssertNil(pendingWipeStore.load(), "pending must be dropped once maxAttempts is reached")
        _ = store
    }

    func testFailedConfirmationDroppedAtMaxAttempts() async throws {
        // Wipe still requested, but the confirmation keeps failing: after maxAttempts
        // the dead token must not linger in the Keychain.
        var almostThere = pending
        almostThere.attempts = PendingWipeStore.maxAttempts - 1
        try pendingWipeStore.save(almostThere)
        mockChecker.checkWipeResult = .success(true)
        mockChecker.confirmWipeResult = false

        let store = await makeStore(credentials: nil) // retained: the resolving task is [weak self]
        await waitFor { self.mockChecker.confirmWipeCalls.count == 1 }
        await waitFor { self.pendingWipeStore.load() == nil }

        XCTAssertNil(pendingWipeStore.load(), "pending must be dropped after maxAttempts failed confirmations")
        _ = store
    }
}
