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
    let fileid: Int64
    let dayid: Int
    let image: UIImage
    let yearsAgo: Int
}

struct OnThisDayEntry: TimelineEntry {
    enum Content {
        /// Nothing was ever prepared: the app has to open once.
        case notLoaded
        /// Prepared, but no photo was taken on this date in past years.
        case noMemories
        /// `confirmingHide`: the main photo is the one the user asked to remove.
        case memories([MemoryImage], confirmingHide: Bool)
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
        let asked = cache.photoAskedToHide(now: now)
        guard !schedule.items.isEmpty else {
            let content: OnThisDayEntry.Content = cache.hasDay(today) ? .noMemories : .notLoaded
            return Timeline(entries: [OnThisDayEntry(date: now, content: content)], policy: .after(schedule.reloadAt))
        }
        let entries = schedule.items.map { item in
            let images = ([item.memory] + item.upcoming).compactMap { entry in
                Self.thumbnail(at: cache.imageURL(for: entry)).map { MemoryImage(fileid: entry.fileid, dayid: entry.dayid, image: $0, yearsAgo: entry.yearsAgo) }
            }
            return OnThisDayEntry(
                date: item.date,
                content: images.isEmpty
                    ? .notLoaded : .memories(images, confirmingHide: images[0].fileid == asked))
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
        case .memories(let images, let confirmingHide):
            // The photos are the widget's background: from iOS 17 the content is inset by the
            // system margins, only the background reaches the edges (no black borders).
            let shown = Array(images.prefix(family == .systemMedium ? 3 : 1))
            Group {
                if confirmingHide {
                    HideQuestion(fileid: shown[0].fileid)
                } else {
                    Foreground(images: shown, canSkip: images.count > 1)
                }
            }
            .widgetURL(confirmingHide ? nil : shown[0].link)
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

/// What sits over the photos: the caption, the cross and the "next" button.
private struct Foreground: View {
    let images: [MemoryImage]
    let canSkip: Bool

    private var memory: MemoryImage { images[0] }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            smallPhotoLinks
            HideButton(fileid: memory.fileid)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .bottom) {
                Text("\(memory.yearsAgo) years ago")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
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

extension Foreground {
    /// Tapping the main photo opens it (`widgetURL`); the small photos of the medium widget
    /// open themselves. Links sit in the foreground: the background cannot be tapped.
    @ViewBuilder
    fileprivate var smallPhotoLinks: some View {
        if images.count > 1 {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Color.clear.frame(width: proxy.size.width * 0.58)
                    VStack(spacing: 2) {
                        ForEach(Array(images.dropFirst().enumerated()), id: \.offset) { _, image in
                            Link(destination: image.link) { Color.clear.contentShape(Rectangle()) }
                        }
                    }
                }
            }
        }
    }
}

extension MemoryImage {
    /// Opens this photo in the app.
    var link: URL { MemoryDeepLink(dayid: dayid, fileid: fileid).url }
}

/// The widget's own "modal": widgets cannot show alerts or react to a long press, so the cross
/// turns the widget into a question with two buttons (iOS 17+, like the cross itself).
private struct HideQuestion: View {
    let fileid: Int64

    var body: some View {
        if #available(iOS 17.0, *) {
            VStack(spacing: 10) {
                Text("Remove this photo from the widget?")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Button(intent: CancelHideMemoryIntent()) {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .tint(.gray)
                    Button(intent: ConfirmHideMemoryIntent(fileid: Int(fileid))) {
                        Text("Remove").frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.65))
        }
    }
}

/// Small cross on the main photo: removes it from the widget for good (iOS 17+).
private struct HideButton: View {
    let fileid: Int64

    var body: some View {
        if #available(iOS 17.0, *) {
            Button(intent: HideMemoryIntent(fileid: Int(fileid))) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.3), in: Circle())
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
