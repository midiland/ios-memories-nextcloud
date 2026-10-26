import AppIntents
import WidgetKit

/// "Next photo" button of the widget (iOS 17+): moves the cursor of the day, then WidgetKit
/// rebuilds the timeline, which now starts further in the day's memories.
@available(iOS 17.0, *)
struct NextMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Next memory"

    func perform() async throws -> some IntentResult {
        MemoryCache().advanceCursor(forDay: MemoryDay.id(of: Date()))
        return .result()
    }
}
