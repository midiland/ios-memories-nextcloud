import Foundation

/// When the widget shows which memory. Pure logic, shared with the widget target.
///
/// The day is cut into slots; slot `k` of the day always shows memory `k % count`, so the photo
/// on screen does not depend on when the timeline happened to be built.
enum MemoryTimeline {
    /// How long a memory stays on screen. iOS limits how often a widget may reload, but a
    /// timeline lets it change photos without any reload.
    static let slotDuration: TimeInterval = 30 * 60
    /// Most timeline entries built at once.
    static let maxSlots = 12
    /// Retry delay when nothing is cached yet (the app has to run to fill the cache).
    static let emptyRetryInterval: TimeInterval = 3 * 3600

    struct Item: Equatable {
        let date: Date
        let memory: MemoryEntry
        /// The memory of the following slot, for the widget sizes that show two photos.
        let next: MemoryEntry?
    }

    struct Schedule: Equatable {
        let items: [Item]
        /// When the widget should ask for a new timeline.
        let reloadAt: Date
    }

    static func schedule(entries: [MemoryEntry], now: Date, calendar: Calendar = .current) -> Schedule {
        let startOfDay = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(86_400)
        guard !entries.isEmpty else {
            return Schedule(items: [], reloadAt: min(now.addingTimeInterval(emptyRetryInterval), tomorrow))
        }

        let firstSlot = Int(now.timeIntervalSince(startOfDay) / slotDuration)
        var items: [Item] = []
        for index in 0..<maxSlots {
            let slot = firstSlot + index
            let start = startOfDay.addingTimeInterval(Double(slot) * slotDuration)
            // The first item starts now (its slot began earlier); a slot past midnight belongs
            // to tomorrow's memories, which are not known yet.
            guard start < tomorrow else { break }
            items.append(Item(
                date: index == 0 ? now : start,
                memory: entries[slot % entries.count],
                next: entries.count > 1 ? entries[(slot + 1) % entries.count] : nil))
        }
        let lastEnd = startOfDay.addingTimeInterval(Double(firstSlot + items.count) * slotDuration)
        return Schedule(items: items, reloadAt: min(lastEnd, tomorrow))
    }
}
