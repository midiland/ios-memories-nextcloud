import Foundation
import WidgetKit

/// Decides when the widget's memories are refreshed, and runs the refresh.
///
/// Triggers: the app coming to the foreground (`refreshIfNeeded`) and the periodic background
/// task (`refresh`). Nothing is downloaded unless one of our widgets is on a home screen:
/// without a widget the memories would be photos downloaded for nothing.
@MainActor
final class MemoryRefreshService {
    /// Identifier of the background refresh task (also in `BGTaskSchedulerPermittedIdentifiers`).
    static let backgroundTaskIdentifier = "fr.midiland.memories.refresh-memories"
    /// Earliest start of the next background refresh. iOS decides the real time.
    static let backgroundInterval: TimeInterval = 12 * 3600
    /// Minimum delay between two foreground attempts, so a failing server is not hammered.
    static let minimumAttemptInterval: TimeInterval = 15 * 60

    private let refresher: MemoryRefresher
    private let cache: MemoryCache
    private let calendar: Calendar
    private let now: () -> Date
    private let hasWidget: () async -> Bool
    private let widgetsDidChange: () -> Void
    private var lastAttempt: Date?
    private var isRefreshing = false

    init(
        fetcher: OnThisDayFetching = NextcloudClient(),
        cache: MemoryCache = MemoryCache(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        hasWidget: @escaping () async -> Bool = MemoryRefreshService.hasInstalledWidget,
        widgetsDidChange: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        refresher = MemoryRefresher(fetcher: fetcher, cache: cache, calendar: calendar)
        self.cache = cache
        self.calendar = calendar
        self.now = now
        self.hasWidget = hasWidget
        self.widgetsDidChange = widgetsDidChange
    }

    /// Whether at least one of the app's widgets is placed on a screen.
    nonisolated static func hasInstalledWidget() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                if case .success(let configurations) = result {
                    continuation.resume(returning: !configurations.isEmpty)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Whether the cache already covers today and the days ahead.
    func isUpToDate() -> Bool {
        let today = OnThisDay.dayId(of: now(), calendar: calendar)
        return (0..<MemoryRefresher.daysAhead).allSatisfy { cache.hasDay(today + $0) }
    }

    /// Foreground trigger: refreshes only when the cache is incomplete and the last attempt is
    /// not recent.
    func refreshIfNeeded(credentials: Credentials) async {
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.minimumAttemptInterval { return }
        guard !isUpToDate() else { return }
        await refresh(credentials: credentials)
    }

    /// Refreshes now (background task). Returns whether the cache was updated.
    @discardableResult
    func refresh(credentials: Credentials) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = now()

        guard await hasWidget() else {
            // The widget was removed: free the photos until it is added again.
            cache.removeAll()
            return false
        }
        do {
            let stored = try await refresher.refresh(credentials: credentials, now: now())
            if stored > 0 { widgetsDidChange() }
            return stored > 0
        } catch AppError.notAuthenticated {
            // Revoked credentials: the session ends when the app is next opened.
            cache.removeAll()
            widgetsDidChange()
            return false
        } catch {
            Log.photos.error("Memories refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
