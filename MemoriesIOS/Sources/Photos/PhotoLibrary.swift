import Photos
import UniformTypeIdentifiers

/// Read-only access to the device photo library (PhotoKit): permission, folders, assets
/// and their original files. Metadata only: image data is rendered by `LocalImageRenderer`.
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    /// Called (on a PhotoKit queue) when the library changes, once `observeChanges()` was called.
    var onChange: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var isObserving = false

    deinit {
        if isObserving { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    /// Starts change notifications. Only once access is granted: registering earlier
    /// may show the permission prompt.
    func observeChanges() {
        guard Self.isAuthorized else { return }
        let start = lock.withLock { () -> Bool in
            defer { isObserving = true }
            return !isObserving
        }
        if start { PHPhotoLibrary.shared().register(self) }
    }

    // MARK: - Permission

    /// Full or limited access granted.
    static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Shows the iOS prompt if the user has not answered yet. Returns whether access is granted.
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Folders and assets

    /// The whole library, then the user's albums.
    func folders() -> [LocalFolder] {
        guard Self.isAuthorized else { return [] }
        var folders = [LocalFolder(id: LocalFolder.libraryId, name: String(localized: "All photos"), enabled: true)]
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { album, _, _ in
            folders.append(LocalFolder(id: album.localIdentifier, name: album.localizedTitle ?? "", enabled: false))
        }
        return folders
    }

    /// Photos of the enabled folders (videos are not supported yet), newest first.
    func assets(inFolders folderIds: Set<String>) -> [LocalAsset] {
        guard Self.isAuthorized, !folderIds.isEmpty else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if folderIds.contains(LocalFolder.libraryId) {
            return Self.convert(PHAsset.fetchAssets(with: options))
        }
        var seen = Set<String>()
        var result: [LocalAsset] = []
        let albums = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: Array(folderIds), options: nil)
        albums.enumerateObjects { album, _, _ in
            for asset in Self.convert(PHAsset.fetchAssets(in: album, options: options)) where seen.insert(asset.localIdentifier).inserted {
                result.append(asset)
            }
        }
        return result.sorted { $0.creationDate > $1.creationDate }
    }

    /// Original file of each asset (name, size, type). Assets without a resource are omitted.
    func resources(for localIdentifiers: [String]) -> [String: LocalResource] {
        guard Self.isAuthorized, !localIdentifiers.isEmpty else { return [:] }
        var result: [String: LocalResource] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil).enumerateObjects { asset, _, _ in
            if let resource = Self.originalResource(of: asset) {
                result[asset.localIdentifier] = resource
            }
        }
        return result
    }

    func phAsset(_ localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }

    // MARK: - Private

    private static func convert(_ fetch: PHFetchResult<PHAsset>) -> [LocalAsset] {
        var assets: [LocalAsset] = []
        assets.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            assets.append(LocalAsset(
                localIdentifier: asset.localIdentifier,
                creationDate: date,
                modificationDate: asset.modificationDate,
                width: asset.pixelWidth,
                height: asset.pixelHeight,
                isVideo: asset.mediaType == .video
            ))
        }
        return assets
    }

    /// The unedited original file (`.photo` / `.video`), as uploaded by the Nextcloud app.
    private static func originalResource(of asset: PHAsset) -> LocalResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary: PHAssetResourceType = asset.mediaType == .video ? .video : .photo
        guard let resource = resources.first(where: { $0.type == primary }) ?? resources.first else { return nil }
        let type = UTType(resource.uniformTypeIdentifier)
        return LocalResource(
            basename: resource.originalFilename,
            size: fileSize(of: resource),
            mimetype: type?.preferredMIMEType ?? "application/octet-stream"
        )
    }

    /// File size without reading the file: `PHAssetResource` has no public API for it, but exposes
    /// a `fileSize` key (widely used). Checked first so a future iOS without it cannot crash.
    private static func fileSize(of resource: PHAssetResource) -> Int64? {
        guard resource.responds(to: NSSelectorFromString("fileSize")) else { return nil }
        return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value
    }
}
