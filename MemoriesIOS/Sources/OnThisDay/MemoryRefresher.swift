import Foundation

/// The two server calls the refresher needs (`NextcloudClient` conforms; tests use a fake).
protocol OnThisDayFetching {
    func photos(onDays dayIds: [Int], credentials: Credentials) async throws -> [ServerPhoto]
    func preview(fileid: Int64, size: Int, credentials: Credentials) async throws -> Data
}

extension NextcloudClient: OnThisDayFetching {}

/// Prepares the widget's memories: for today and the next few days, asks the server for the
/// photos of that date in past years, picks some, downloads their thumbnails and stores
/// everything in the `MemoryCache`.
struct MemoryRefresher {
    /// Days prepared ahead, today included: a skipped background refresh stays invisible.
    static let daysAhead = 5
    /// Thumbnail edge in pixels (the widget is small: keeps the extension's memory low).
    static let thumbnailSize = 600

    let fetcher: OnThisDayFetching
    let cache: MemoryCache
    let calendar: Calendar

    init(fetcher: OnThisDayFetching, cache: MemoryCache = MemoryCache(), calendar: Calendar = .current) {
        self.fetcher = fetcher
        self.cache = cache
        self.calendar = calendar
    }

    /// Refreshes the cache. A day whose request fails is skipped (the other days still get
    /// stored); only an authentication failure aborts, so the caller can react to it.
    /// Returns the number of days stored.
    @discardableResult
    func refresh(credentials: Credentials, now: Date = Date()) async throws -> Int {
        let today = OnThisDay.dayId(of: now, calendar: calendar)
        var days: [Int: [MemoryEntry]] = [:]
        var images: [String: Data] = [:]

        for offset in 0..<Self.daysAhead {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let displayDay = today + offset
            // Past days are never kept; days already prepared are only refreshed for today.
            if offset > 0, cache.hasDay(displayDay) { continue }

            let photos: [ServerPhoto]
            do {
                photos = try await fetcher.photos(
                    onDays: OnThisDay.dayIds(for: date, calendar: calendar), credentials: credentials)
            } catch AppError.notAuthenticated {
                throw AppError.notAuthenticated
            } catch {
                continue
            }

            let years = OnThisDay.groupByYear(photos, todayDayId: displayDay)
            var entries: [MemoryEntry] = []
            for pick in OnThisDay.pick(from: years, seed: displayDay) {
                let name = MemoryCache.imageName(fileid: pick.photo.fileid)
                if images[name] == nil, !hasImage(named: name) {
                    do {
                        images[name] = try await fetcher.preview(
                            fileid: pick.photo.fileid, size: Self.thumbnailSize, credentials: credentials)
                    } catch AppError.notAuthenticated {
                        throw AppError.notAuthenticated
                    } catch {
                        continue
                    }
                }
                entries.append(MemoryEntry(
                    fileid: pick.photo.fileid, dayid: pick.photo.dayid,
                    yearsAgo: pick.yearsAgo, imageName: name))
            }
            days[displayDay] = entries
        }

        guard !days.isEmpty else { return 0 }
        try cache.store(days: days, images: images)
        cache.prune(before: today)
        return days.count
    }

    private func hasImage(named name: String) -> Bool {
        let probe = MemoryEntry(fileid: 0, dayid: 0, yearsAgo: 0, imageName: name)
        return FileManager.default.fileExists(atPath: cache.imageURL(for: probe).path)
    }
}
