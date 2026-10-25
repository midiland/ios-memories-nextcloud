import Foundation

/// Extracts the ZIP the server sends for an album or a multiple selection
/// (`DownloadController::multiple`, ZipStreamer with ZIP64), like `InAppDownloader.unzipPublic` on Android.
enum ZipExtractor {
    /// Whether the file starts with a ZIP local file header (`PK\u{3}\u{4}`), whatever its name.
    static func isZip(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    /// Extracts every file entry into `folder` (flat) and returns the extracted files.
    /// Entry names are reduced to a safe base name (no Zip Slip), duplicates get a suffix.
    /// `progress(done, total)` is called after each file, with the number of files extracted
    /// so far and the total number of extractable file entries (issue #14).
    ///
    /// Throws before writing anything if the declared sizes do not fit in `availableCapacity`
    /// (bytes free on the volume of `folder`), stops at the first entry that holds more than it
    /// declares, honours task cancellation, and removes what it extracted when it fails.
    static func extract(
        _ zip: URL,
        into folder: URL,
        progress: (@Sendable (Int, Int) -> Void)? = nil,
        availableCapacity: (URL) -> Int64? = freeSpace
    ) throws -> [URL] {
        let archive = try ZipArchive(url: zip)
        // Only entries with a safe name count towards the total (issue #14).
        let entries = archive.entries.filter { !$0.isDirectory && safeName($0.path) != nil }
        let total = entries.count

        let needed = entries.reduce(UInt64(0)) { $0 &+ $1.uncompressedSize }
        if let available = availableCapacity(folder), needed > UInt64(max(0, available)) {
            throw ZipArchive.ZipError.insufficientSpace
        }

        var used = Set<String>()
        var files: [URL] = []
        var done = 0
        do {
            for entry in entries {
                try Task.checkCancellation()
                guard let name = safeName(entry.path) else { continue }
                let destination = folder.appendingPathComponent(uniqueName(name, taken: &used))
                try archive.extract(entry, to: destination)
                files.append(destination)
                done += 1
                progress?(done, total)
            }
        } catch {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        return files
    }

    /// Bytes available for important data on the volume holding `url`; `nil` if unknown.
    static func freeSpace(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    /// Base name of an entry path; `nil` for metadata (`__MACOSX/…`, `.DS_Store`) and empty names.
    static func safeName(_ path: String) -> String? {
        guard !path.hasSuffix("/"), !path.hasSuffix("\\") else { return nil }
        let components = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard !components.contains("__MACOSX"), let last = components.last else { return nil }
        let name = last.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.hasPrefix("."), name != ".." else { return nil }
        return name
    }

    /// `name`, or `name (2).ext`, `name (3).ext`… if already taken (case-insensitive file systems).
    static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = name
        var index = 2
        while taken.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            index += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }
}
