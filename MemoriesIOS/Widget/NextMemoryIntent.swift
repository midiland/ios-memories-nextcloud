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

/// Cross of the widget (iOS 17+): asks whether to remove this photo (the widget then shows the
/// question; nothing is hidden yet).
@available(iOS 17.0, *)
struct HideMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Hide memory"

    @Parameter(title: "Photo")
    var fileid: Int

    init() {}

    init(fileid: Int) {
        self.fileid = fileid
    }

    func perform() async throws -> some IntentResult {
        MemoryCache().askToHide(fileid: Int64(fileid))
        return .result()
    }
}

/// "Remove" in the widget's question: never shows this photo again.
@available(iOS 17.0, *)
struct ConfirmHideMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Confirm hiding memory"

    @Parameter(title: "Photo")
    var fileid: Int

    init() {}

    init(fileid: Int) {
        self.fileid = fileid
    }

    func perform() async throws -> some IntentResult {
        MemoryCache().hide(fileid: Int64(fileid))
        return .result()
    }
}

/// "Cancel" in the widget's question.
@available(iOS 17.0, *)
struct CancelHideMemoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel hiding memory"

    func perform() async throws -> some IntentResult {
        MemoryCache().cancelHide()
        return .result()
    }
}
