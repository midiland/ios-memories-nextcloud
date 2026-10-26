import ImageIO
import SwiftUI
import WidgetKit

@main
struct MemoriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
    }
}

/// "On this day" photos from past years, on the unlocked home screen only.
struct OnThisDayWidget: Widget {
    static let kind = "OnThisDayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OnThisDayProvider()) { entry in
            OnThisDayView(entry: entry)
        }
        .configurationDisplayName("Memories")
        .description("Your photos from past years, on this day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct MemoryImage {
    let image: UIImage
    let yearsAgo: Int
}

struct OnThisDayEntry: TimelineEntry {
    enum Content {
        /// Nothing was ever prepared: the app has to open once.
        case notLoaded
        /// Prepared, but no photo was taken on this date in past years.
        case noMemories
        case memories([MemoryImage])
    }

    let date: Date
    let content: Content
}

struct OnThisDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: Date(), content: .notLoaded)
    }

    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        completion(timeline(now: Date()).entries.first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        completion(timeline(now: Date()))
    }

    private func timeline(now: Date) -> Timeline<OnThisDayEntry> {
        let cache = MemoryCache()
        let today = Self.dayId(of: now)
        let schedule = MemoryTimeline.schedule(entries: cache.entries(forDay: today), now: now)
        guard !schedule.items.isEmpty else {
            let content: OnThisDayEntry.Content = cache.hasDay(today) ? .noMemories : .notLoaded
            return Timeline(entries: [OnThisDayEntry(date: now, content: content)], policy: .after(schedule.reloadAt))
        }
        let entries = schedule.items.map { item in
            let images = [item.memory, item.next].compactMap { $0 }.compactMap { entry in
                Self.thumbnail(at: cache.imageURL(for: entry)).map { MemoryImage(image: $0, yearsAgo: entry.yearsAgo) }
            }
            return OnThisDayEntry(date: item.date, content: images.isEmpty ? .notLoaded : .memories(images))
        }
        return Timeline(entries: entries, policy: .after(schedule.reloadAt))
    }

    /// Same day id as the app (`OnThisDay.dayId`): the UTC day number of the local calendar day.
    private static func dayId(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day))!
        return Int(day.timeIntervalSince1970) / 86_400
    }

    /// Decodes a downscaled image: a widget extension has a small memory budget.
    private static func thumbnail(at url: URL) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - Views

struct OnThisDayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OnThisDayEntry

    var body: some View {
        switch entry.content {
        case .memories(let images):
            if family == .systemMedium, images.count > 1 {
                HStack(spacing: 2) {
                    MemoryTile(memory: images[0])
                    MemoryTile(memory: images[1])
                }
                .widgetBackground(Color.black)
            } else {
                MemoryTile(memory: images[0])
                    .widgetBackground(Color.black)
            }
        case .noMemories:
            Message(text: "No memories today").widgetBackground(Color(.systemBackground))
        case .notLoaded:
            Message(text: "Open Memories to load your memories").widgetBackground(Color(.systemBackground))
        }
    }
}

/// A photo filling its space, with the Apple Photos style caption over a gradient.
private struct MemoryTile: View {
    let memory: MemoryImage

    var body: some View {
        // The image is a background so it fills the tile without growing the layout.
        Color.clear
            .overlay(
                Image(uiImage: memory.image)
                    .resizable()
                    .scaledToFill()
            )
            .overlay(alignment: .bottomLeading) {
                Text("\(memory.yearsAgo) years ago")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    )
            }
            .clipped()
    }
}

private struct Message: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .padding(8)
    }
}

private extension View {
    /// `containerBackground` is required from iOS 17 (it also gives the full-bleed photo).
    @ViewBuilder
    func widgetBackground<Background: View>(_ background: Background) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { background }
        } else {
            ZStack { background; self }
        }
    }
}
