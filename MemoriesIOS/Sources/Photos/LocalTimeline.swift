import Foundation

/// Device photos for the Memories timeline (counterpart of `TimelineRepositoryImpl.kt`),
/// answering the bridge routes `/api/days`, `/api/days/{id}`, `/api/image/info/{id}` and serving
/// the JPEGs of the local server.
///
/// Device photos that already exist on the server are left out (`PhotoMatcher`): the server copy is
/// shown instead. The library is read on demand (metadata only); a day's original files are only
/// looked up when that day is displayed.
actor LocalTimeline: LocalMediaProvider {
    private let library: PhotoLibrary
    private let settings: LocalPhotoSettings
    private let serverDays: ServerDayClient
    private let remoteCopies: RemoteCopyStore
    private let renderer = LocalImageRenderer()
    private let timeZone: @Sendable () -> TimeZone

    /// Enabled assets grouped by day; `nil` until read, or after a library / settings change.
    private var days: [Int: [LocalAsset]]?
    private var resources: [String: LocalResource] = [:]
    /// Lookups for the image routes, filled as days are served.
    private var byFileId: [Int64: LocalAsset] = [:]
    private var byAuid: [String: String] = [:]
    private var byBuid: [String: String] = [:]

    init(
        credentials: Credentials,
        library: PhotoLibrary = PhotoLibrary(),
        settings: LocalPhotoSettings = LocalPhotoSettings(),
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.library = library
        self.settings = settings
        self.timeZone = timeZone
        serverDays = ServerDayClient(credentials: credentials)
        remoteCopies = RemoteCopyStore(credentials: credentials)
    }

    /// Device photos are shown: opted in, iOS access granted.
    nonisolated var isEnabled: Bool { settings.isEnabled && PhotoLibrary.isAuthorized }

    /// Forgets the cached library (photo library or folder settings changed).
    func invalidate() async {
        days = nil
        await serverDays.invalidate()
    }

    // MARK: - Bridge routes

    /// `/api/days`: `[{ dayid, count }]`, newest first, counting device-only photos.
    func daysJSON() -> String {
        let counts = loadDays()
            .map { dayId, assets in (dayId, assets.filter { !remoteCopies.contains($0.localIdentifier) }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.0 > $1.0 }
        #if DEBUG
        Log.photos.debug("Device days: \(counts.count) days, \(counts.map(\.1).reduce(0, +)) device-only photos")
        #endif
        return Self.json(counts.map { ["dayid": $0.0, "count": $0.1] })
    }

    /// `/api/days/{id}`: device-only photos of the day.
    func dayJSON(_ dayId: Int) async -> String {
        let assets = loadDays()[dayId] ?? []
        guard !assets.isEmpty else { return "[]" }
        loadResources(for: assets)
        let local = await deviceOnly(assets, dayId: dayId)
        return Self.json(local.map { photoJSON($0, dayId: dayId) })
    }

    /// `/api/image/info/{id}`, `nil` if unknown.
    func imageInfoJSON(fileId: Int64) -> String? {
        guard let asset = asset(fileId: fileId) else { return nil }
        let dayId = asset.dayId(in: timeZone())
        var info = photoJSON(asset, dayId: dayId)
        info["datetaken"] = PhotoIDs.wallClockEpoch(asset.creationDate, in: timeZone())
        info["mtime"] = Int((asset.modificationDate ?? asset.creationDate).timeIntervalSince1970)
        info["permissions"] = ""
        info["exif"] = [String: Any]()
        return Self.json(info)
    }

    /// `nativex.setHasRemote(auids, buids, true)`: the frontend found server copies.
    func markHasRemote(auids: [String], buids: [String]) {
        let ids = auids.compactMap { byAuid[$0] } + buids.compactMap { byBuid[$0] }
        remoteCopies.insert(ids)
    }

    // MARK: - LocalMediaProvider

    func preview(fileId: Int64, width: Int?, height: Int?) async -> Data? {
        guard let asset = asset(fileId: fileId), let phAsset = library.phAsset(asset.localIdentifier) else { return nil }
        return await renderer.preview(phAsset, width: width, height: height)
    }

    func full(auid: String, longEdge: Int?) async -> Data? {
        guard let id = byAuid[auid], let phAsset = library.phAsset(id) else { return nil }
        return await renderer.full(phAsset, longEdge: longEdge)
    }

    // MARK: - Private

    /// Asset by `fileid`; indexes the whole library if the day was not served yet.
    private func asset(fileId: Int64) -> LocalAsset? {
        if let asset = byFileId[fileId] { return asset }
        for asset in loadDays().values.joined() where byFileId[asset.fileId] == nil {
            byFileId[asset.fileId] = asset
        }
        return byFileId[fileId]
    }

    private func loadDays() -> [Int: [LocalAsset]] {
        if let days { return days }
        guard isEnabled else { return [:] }
        library.observeChanges()
        let folders = LocalFolder.merge(available: library.folders(), saved: settings.savedFolders)
        let enabled = Set(folders.filter(\.enabled).map(\.id))
        let zone = timeZone()
        let loaded = Dictionary(grouping: library.assets(inFolders: enabled)) { $0.dayId(in: zone) }
        days = loaded
        return loaded
    }

    private func loadResources(for assets: [LocalAsset]) {
        let missing = assets.map(\.localIdentifier).filter { resources[$0] == nil }
        resources.merge(library.resources(for: missing)) { _, new in new }
    }

    /// Assets of `dayId` without a server copy. The server photos of the neighbouring days are
    /// included: the server's day can differ (timezone of the capture vs the device's).
    private func deviceOnly(_ assets: [LocalAsset], dayId: Int) async -> [LocalAsset] {
        let candidates = assets.map(candidate)
        let ids = assets.map(\.localIdentifier)
        do {
            let server = try await serverDays.photos(days: [dayId - 1, dayId, dayId + 1])
            let result = PhotoMatcher.match(candidates, against: server)
            remoteCopies.update(checked: ids, matched: result.matched)
            #if DEBUG
            Log.photos.debug("""
                Day \(dayId): \(assets.count) device photos, \(result.byIdentifier) matched by id, \
                \(result.byFingerprint) by fingerprint, \(assets.count - result.matched.count) device-only
                """)
            #endif
            return assets.filter { !result.matched.contains($0.localIdentifier) }
        } catch {
            // Offline: rely on the last known matches.
            Log.photos.notice("Server day \(dayId) unavailable: \(String(describing: error), privacy: .public)")
            return assets.filter { !remoteCopies.contains($0.localIdentifier) }
        }
    }

    private func candidate(_ asset: LocalAsset) -> PhotoMatcher.Candidate {
        let ids = identifiers(asset)
        return PhotoMatcher.Candidate(
            id: asset.localIdentifier,
            epoch: asset.epoch,
            wallClockEpoch: PhotoIDs.wallClockEpoch(asset.creationDate, in: timeZone()),
            width: asset.width,
            height: asset.height,
            isVideo: asset.isVideo,
            auid: ids.auid,
            buid: ids.buid
        )
    }

    /// `auid`/`buid` from the original file; without a known size they cannot match the server's.
    private func identifiers(_ asset: LocalAsset) -> (auid: String?, buid: String?) {
        guard let resource = resources[asset.localIdentifier], let size = resource.size else { return (nil, nil) }
        return (PhotoIDs.auid(epoch: asset.epoch, size: size), PhotoIDs.buid(basename: resource.basename, size: size))
    }

    /// Photo object expected by the frontend (`IPhoto`, like `PhotoMapper.toJson` on Android).
    private func photoJSON(_ asset: LocalAsset, dayId: Int) -> [String: Any] {
        let resource = resources[asset.localIdentifier]
        let ids = identifiers(asset)
        // The viewer looks the full image up by auid: always provide one.
        let auid = ids.auid ?? PhotoIDs.auid(epoch: asset.epoch, size: 0)
        byFileId[asset.fileId] = asset
        byAuid[auid] = asset.localIdentifier
        if let buid = ids.buid { byBuid[buid] = asset.localIdentifier }

        var photo: [String: Any] = [
            "fileid": asset.fileId,
            "basename": resource?.basename ?? "",
            "mimetype": resource?.mimetype ?? "image/jpeg",
            "w": asset.width,
            "h": asset.height,
            "size": resource?.size ?? 0,
            "etag": String(Int((asset.modificationDate ?? asset.creationDate).timeIntervalSince1970)),
            "epoch": asset.epoch,
            "dayid": dayId,
            "auid": auid,
            "local_has_remote": false,
        ]
        if let buid = ids.buid { photo["buid"] = buid }
        return photo
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
