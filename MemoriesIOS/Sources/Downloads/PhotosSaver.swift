import Photos

/// Saves downloaded photos and videos to the photo library, skipping those already there,
/// and gathers them in an album named after the Memories album (full access only).
/// Counterpart of `InAppDownloader.downloadPublic` on Android, which saves to Downloads/memories/.
struct PhotosSaver {
    let library: PhotoLibrary

    struct Result: Equatable {
        var saved = 0
        var alreadyInPhotos = 0
        var failed = 0
    }

    /// Call once access is granted (`PhotosAccessPrompt`). Files are moved into the library.
    func save(_ media: [MediaFile], album title: String?) async -> Result {
        let duplicates = await DuplicateFinder(library: library).find(in: media)
        var result = Result(alreadyInPhotos: duplicates.duplicates.count)
        var albumAssets = Array(duplicates.deviceCopies)

        for (index, file) in media.enumerated() where !duplicates.duplicates.contains(index) {
            if let id = await create(file) {
                result.saved += 1
                albumAssets.append(id)
            } else {
                result.failed += 1
            }
        }

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           !albumAssets.isEmpty, await PhotosAccessPrompt.hasFullAccess {
            await addToAlbum(named: title, assets: albumAssets)
        }
        return result
    }

    /// One change per file: a format Photos rejects does not cancel the others.
    private func create(_ file: MediaFile) async -> String? {
        let created = CreatedAsset()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = file.url.lastPathComponent
                options.shouldMoveFile = true
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: file.isVideo ? .video : .photo, fileURL: file.url, options: options)
                created.localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
            return created.localIdentifier
        } catch {
            Log.nativex.error("Save to Photos failed for \(file.url.lastPathComponent, privacy: .private): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Adds the assets to the user album titled `title`, created if needed (the first one found
    /// otherwise: albums can share a title).
    private func addToAlbum(named title: String, assets ids: [String]) async {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", title)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = existing.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                    ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                request.addAssets(assets)
            }
        } catch {
            Log.nativex.error("Album update failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Carries the placeholder ID out of the PhotoKit change block.
private final class CreatedAsset: @unchecked Sendable {
    var localIdentifier: String?
}
