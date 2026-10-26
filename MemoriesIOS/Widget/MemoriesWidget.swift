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
        let today = MemoryDay.id(of: now)
        let schedule = MemoryTimeline.schedule(
            entries: cache.entries(forDay: today), now: now, offset: cache.cursor(forDay: today))
        guard !schedule.items.isEmpty else {
            let content: OnThisDayEntry.Content = cache.hasDay(today) ? .noMemories : .notLoaded
            return Timeline(entries: [OnThisDayEntry(date: now, content: content)], policy: .after(schedule.reloadAt))
        }
        let entries = schedule.items.map { item in
            let images = ([item.memory] + item.upcoming).compactMap { entry in
                Self.thumbnail(at: cache.imageURL(for: entry)).map { MemoryImage(image: $0, yearsAgo: entry.yearsAgo) }
            }
            return OnThisDayEntry(date: item.date, content: images.isEmpty ? .notLoaded : .memories(images))
        }
        return Timeline(entries: entries, policy: .after(schedule.reloadAt))
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
            // The photos are the widget's background: from iOS 17 the content is inset by the
            // system margins, only the background reaches the edges (no black borders).
            let shown = Array(images.prefix(family == .systemMedium ? 3 : 1))
            Foreground(caption: images[0].yearsAgo, canSkip: images.count > 1)
                .widgetBackground(Photos(images: shown))
        case .noMemories:
            Message(text: "No memories today").widgetBackground(Color(.systemBackground))
        case .notLoaded:
            Message(text: "Open Memories to load your memories").widgetBackground(Color(.systemBackground))
        }
    }
}

/// The photos edge to edge: one for the small widget; on the medium one the main photo on the
/// left and the next ones stacked on the right.
private struct Photos: View {
    let images: [MemoryImage]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                tile(images[0])
                    .frame(width: images.count > 1 ? proxy.size.width * 0.58 : proxy.size.width)
                if images.count > 1 {
                    VStack(spacing: 2) {
                        ForEach(Array(images.dropFirst().enumerated()), id: \.offset) { _, image in
                            tile(image)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ memory: MemoryImage) -> some View {
        Color.black
            .overlay(Image(uiImage: memory.image).resizable().scaledToFill())
            .clipped()
    }
}

/// What sits over the photos: the Apple Photos style caption and the "next" button.
private struct Foreground: View {
    let caption: Int
    let canSkip: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                .opacity(0.9)
            HStack(alignment: .bottom) {
                Text("\(caption) years ago")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                Spacer(minLength: 0)
                if canSkip { NextButton() }
            }
        }
    }
}

/// Interactive widgets (iOS 17) can run an intent on tap: shows the next photo. Widgets cannot
/// be swiped, and older systems keep the automatic rotation only.
private struct NextButton: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: NextMemoryIntent()) {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
        }
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
    /// `containerBackground` is required from iOS 17 and goes edge to edge. Before, the widget
    /// has no margins and the background is simply stacked behind the content.
    @ViewBuilder
    func widgetBackground<Background: View>(_ background: Background) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { background }
        } else {
            ZStack { background; padding(12) }
        }
    }
}
