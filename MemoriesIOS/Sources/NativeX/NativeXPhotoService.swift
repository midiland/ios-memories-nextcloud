import Foundation
import Photos

/// Device photos on the bridge side: permission and folder settings, synchronous state pushed to
/// `nativex.js`, and the local timeline routes (`/api/days`, `/api/days/{id}`, `/api/image/info/{id}`).
///
/// The timeline is only attached in local mode: the frontend loads device images from
/// `location.origin`, which is the local server only in that mode.
@MainActor
final class NativeXPhotoService {
    /// Runs scripts in the page (state updates, timeline refresh events).
    weak var host: NativeXHost?
    /// `nil` until the app is loaded from the local server: no device photos before that.
    var timeline: LocalTimeline?

    private let library: PhotoLibrary
    private let settings = LocalPhotoSettings()
    private var refreshTask: Task<Void, Never>?

    init(library: PhotoLibrary) {
        self.library = library
        library.onChange = { [weak self] in
            Task { @MainActor in self?.libraryDidChange() }
        }
    }

    // MARK: - Synchronous state (`nativex.js`)

    /// `configHasMediaPermission`, `configGetLocalFolders`, `getSyncStatus` (the library is read
    /// on demand: never "syncing").
    var state: [String: Any] {
        ["hasMediaPermission": hasMediaPermission, "localFolders": foldersJSON, "syncStatus": -1]
    }

    private var hasMediaPermission: Bool { settings.isEnabled && PhotoLibrary.isAuthorized }

    private var foldersJSON: String {
        let folders = LocalFolder.merge(available: library.folders(), saved: settings.savedFolders)
        let data = (try? JSONEncoder().encode(folders)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Startup

    /// Whether to open the device setup instead of the timeline (first launch, iOS prompt
    /// never shown). Returns `true` once: the offer is recorded.
    func takeSetupOffer() -> Bool {
        let offer = DeviceSetupRule.shouldOffer(
            alreadyOffered: settings.setupOffered,
            isEnabled: settings.isEnabled,
            status: PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
        if offer { settings.setupOffered = true }
        return offer
    }

    // MARK: - Calls from the frontend

    /// `/api/config/allow_media/{0|1}`: opt in (iOS prompt if needed) or out. The state is pushed
    /// before replying: the frontend reads `configHasMediaPermission()` right after.
    func allowMedia(_ allow: Bool) async {
        settings.isEnabled = allow
        if allow {
            let granted = await library.requestAuthorization()
            Log.photos.notice("Device photos enabled, access granted: \(granted)")
            if granted { library.observeChanges() }
        }
        await timelineChanged()
    }

    /// `nativex.configSetLocalFolders(json)`.
    func setFolders(json: String?) {
        settings.saveFolders(json: json ?? "[]")
        Task { await timelineChanged() }
    }

    /// `nativex.setHasRemote(auids, buids, true)`.
    func setHasRemote(auidsJSON: String?, buidsJSON: String?, value: Bool) {
        guard value, let timeline else { return }
        let auids = Self.strings(auidsJSON)
        let buids = Self.strings(buidsJSON)
        Task { await timeline.markHasRemote(auids: auids, buids: buids) }
    }

    func daysJSON() async -> String {
        guard let timeline else { return "[]" }
        return await timeline.daysJSON()
    }

    func dayJSON(_ dayId: Int) async -> String {
        guard let timeline else { return "[]" }
        return await timeline.dayJSON(dayId)
    }

    func imageInfoJSON(fileId: Int64) async -> String? {
        await timeline?.imageInfoJSON(fileId: fileId)
    }

    // MARK: - Private

    /// Library changed (new photo, deletion…): refresh once things settle.
    private func libraryDidChange() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await timelineChanged()
        }
    }

    /// Forgets the cached library, updates the page state and asks the frontend to refetch
    /// (`nativex:db:updated` clears its local day cache, like `JsEventBus.kt` on Android).
    private func timelineChanged() async {
        await timeline?.invalidate()
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let json = String(data: data, encoding: .utf8)
        else { return }
        host?.nativeXEvaluate("""
            window.__nativexSetState?.(\(json));
            window._nc_event_bus?.emit('nativex:db:updated', null);
            window._nc_event_bus?.emit('memories:timeline:soft-refresh', null);
            """)
    }

    private static func strings(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
