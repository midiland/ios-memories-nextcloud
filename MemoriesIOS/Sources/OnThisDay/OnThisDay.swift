import Foundation

/// "On this day" memories: pure logic shared by the app and the widget cache.
///
/// Memories has no dedicated endpoint: the frontend (`dav/onthisday.ts`, `OnThisDay.vue`) asks for
/// the days around today's date in every past year, groups the photos by anniversary and picks a
/// few per year. This mirrors that algorithm.
enum OnThisDay {
    /// Photos of one anniversary, e.g. everything taken around this date 3 years ago.
    struct Year: Equatable {
        let yearsAgo: Int
        let photos: [ServerPhoto]
    }

    /// Server day id of the calendar day of `date` in `calendar` (the user's local day).
    static func dayId(of date: Date, calendar: Calendar = .current) -> Int {
        MemoryDay.id(of: date, calendar: calendar)
    }

    /// Day ids to query: for each of the last `maxYears` years, the days within `range` of
    /// today's date. A 29 February rolls over to 1 March in non-leap years, as in the frontend.
    static func dayIds(for date: Date, maxYears: Int = 40, range: Int = 3, calendar: Calendar = .current) -> [Int] {
        guard maxYears > 0, range >= 0 else { return [] }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return [] }

        var ids: [Int] = []
        for ago in 1...maxYears {
            // Out-of-range days (29 Feb) are resolved leniently by `Calendar.date(from:)`.
            let anniversary = DateComponents(calendar: MemoryDay.utc, year: year - ago, month: month, day: day)
            guard let base = MemoryDay.utc.date(from: anniversary) else { continue }
            let baseId = Int(base.timeIntervalSince1970) / MemoryDay.seconds
            for offset in -range...range { ids.append(baseId + offset) }
        }
        return ids
    }

    /// Keeps displayable photos: no videos, no hidden files (`.name`).
    static func displayable(_ photos: [ServerPhoto]) -> [ServerPhoto] {
        photos.filter { !$0.isVideo && !$0.basename.hasPrefix(".") }
    }

    /// Groups photos by anniversary: a gap of more than 30 days between two photos (sorted by
    /// date) starts a new year, which also copes with the year boundary around 1 January.
    /// Most recent anniversary first.
    static func groupByYear(_ photos: [ServerPhoto], todayDayId: Int) -> [Year] {
        let sorted = displayable(photos).sorted { $0.dayid > $1.dayid }
        var groups: [[ServerPhoto]] = []
        var previous = Int.max
        for photo in sorted {
            if groups.isEmpty || abs(previous - photo.dayid) > 30 { groups.append([]) }
            groups[groups.count - 1].append(photo)
            previous = photo.dayid
        }
        return groups.map { group in
            let years = Double(todayDayId - group[0].dayid) / 365.25
            return Year(yearsAgo: max(1, Int(years.rounded())), photos: group)
        }
    }

    /// Picks up to `perYear` photos per anniversary and `maxTotal` overall, spreading the
    /// choice across years (most recent first, one photo per year per round).
    ///
    /// The choice is seeded with `seed` (the day id), so every refresh of the same day yields
    /// the same photos: the widget does not reshuffle when it reloads.
    static func pick(from years: [Year], perYear: Int = 3, maxTotal: Int = 12, seed: Int) -> [(yearsAgo: Int, photo: ServerPhoto)] {
        guard perYear > 0, maxTotal > 0 else { return [] }
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
        // Per-year shuffled picks, in a stable order (photos arrive sorted by date).
        let shuffled = years.map { year in
            (yearsAgo: year.yearsAgo, photos: Array(year.photos.shuffled(using: &generator).prefix(perYear)))
        }
        var result: [(yearsAgo: Int, photo: ServerPhoto)] = []
        for round in 0..<perYear {
            for year in shuffled where round < year.photos.count {
                result.append((year.yearsAgo, year.photos[round]))
                if result.count == maxTotal { return result }
            }
        }
        return result
    }
}

/// SplitMix64: small deterministic generator, so a given seed always shuffles the same way.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
