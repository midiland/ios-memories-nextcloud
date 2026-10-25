import Compression
import Foundation

/// Minimal ZIP reader for the archives of the Memories server (`ZipStreamer`): central directory,
/// ZIP64 records and fields, stored or deflated entries, streamed to disk in chunks.
/// Written for this app because ZIPFoundation rejects the zero-valued ZIP64 fields ZipStreamer
/// writes (weichsel/ZIPFoundation#319) and finds no entry at all.
struct ZipArchive {
    struct Entry: Equatable {
        let path: String
        let method: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
        let isEncrypted: Bool

        var isDirectory: Bool { path.hasSuffix("/") || path.hasSuffix("\\") }
    }

    enum ZipError: Error {
        case notAZip
        case corrupted(String)
        case unsupported(String)
        /// An entry holds more data than its directory declares (zip bomb or corruption).
        case sizeExceeded(String)
        case insufficientSpace
    }

    let url: URL
    let entries: [Entry]

    init(url: URL) throws {
        self.url = url
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        entries = try Self.readCentralDirectory(handle)
    }

    /// Writes the content of `entry` to `destination` (stored or deflate).
    func extract(_ entry: Entry, to destination: URL) throws {
        guard !entry.isEncrypted else { throw ZipError.unsupported("encrypted entry") }
        guard entry.method == 0 || entry.method == 8 else { throw ZipError.unsupported("method \(entry.method)") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // Local header: the name and extra lengths may differ from the central directory's.
        try handle.seek(toOffset: entry.localHeaderOffset)
        let header = try Self.read(handle, 30)
        guard header.uint32(0) == 0x0403_4B50 else { throw ZipError.corrupted("local header") }
        let dataStart = entry.localHeaderOffset + 30 + UInt64(header.uint16(26)) + UInt64(header.uint16(28))
        try handle.seek(toOffset: dataStart)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        var completed = false
        defer {
            try? output.close()
            if !completed { try? FileManager.default.removeItem(at: destination) } // no partial file
        }

        // `write(contentsOf:)` throws (ENOSPC, …); the legacy `write(_:)` raises an Objective-C
        // exception that crashes the app. The decompression callback cannot throw: the first
        // failure is kept and rethrown below, and nothing more is written after it.
        let declared = entry.uncompressedSize
        var written: UInt64 = 0
        var failure: Error?
        func append(_ data: Data) {
            guard failure == nil else { return }
            guard written + UInt64(data.count) <= declared else {
                failure = ZipError.sizeExceeded(entry.path)
                return
            }
            do {
                try output.write(contentsOf: data)
                written += UInt64(data.count)
            } catch {
                failure = error
            }
        }
        let filter = entry.method == 8
            ? try OutputFilter(.decompress, using: .zlib) { data in
                if let data { append(data) }
            }
            : nil

        var remaining = entry.compressedSize
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try Self.read(handle, Int(min(remaining, 1 << 20)))
            remaining -= UInt64(chunk.count)
            if let filter {
                try filter.write(chunk)
            } else {
                append(chunk)
            }
            if let failure { throw failure }
        }
        try filter?.finalize()
        if let failure { throw failure }
        guard written == declared else { throw ZipError.corrupted("size of \(entry.path)") }
        completed = true
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ handle: FileHandle) throws -> [Entry] {
        let fileSize = try handle.seekToEnd()
        // End of central directory: 22 bytes + a comment of up to 64 KiB, at the end of the file.
        let tailSize = min(fileSize, 22 + 0xFFFF)
        try handle.seek(toOffset: fileSize - tailSize)
        let tail = try read(handle, Int(tailSize))
        guard let eocd = lastIndex(of: 0x0605_4B50, in: tail) else { throw ZipError.notAZip }

        var count = UInt64(tail.uint16(eocd + 10))
        var offset = UInt64(tail.uint32(eocd + 16))
        if count == 0xFFFF || offset == 0xFFFF_FFFF {
            // ZIP64 end of central directory, found through its locator just before the EOCD.
            guard eocd >= 20, tail.uint32(eocd - 20) == 0x0706_4B50 else { throw ZipError.corrupted("ZIP64 locator") }
            try handle.seek(toOffset: tail.uint64(eocd - 20 + 8))
            let record = try read(handle, 56)
            guard record.uint32(0) == 0x0606_4B50 else { throw ZipError.corrupted("ZIP64 record") }
            count = record.uint64(32)
            offset = record.uint64(48)
        }

        try handle.seek(toOffset: offset)
        var entries: [Entry] = []
        for _ in 0..<count {
            let header = try read(handle, 46)
            guard header.uint32(0) == 0x0201_4B50 else { throw ZipError.corrupted("central directory") }
            let nameLength = Int(header.uint16(28))
            let extraLength = Int(header.uint16(30))
            let commentLength = Int(header.uint16(32))
            let variable = try read(handle, nameLength + extraLength + commentLength)
            let nameData = variable.prefix(nameLength)
            let flags = header.uint16(8)
            // Bit 11: UTF-8 names; ZipStreamer always sets it. Fall back to Latin-1 otherwise.
            let path = String(data: nameData, encoding: flags & 0x0800 != 0 ? .utf8 : .isoLatin1)
                ?? String(decoding: nameData, as: UTF8.self)

            var sizes = Zip64Fields(
                uncompressed: UInt64(header.uint32(24)),
                compressed: UInt64(header.uint32(20)),
                offset: UInt64(header.uint32(42))
            )
            sizes.apply(extra: variable.dropFirst(nameLength).prefix(extraLength))
            entries.append(Entry(
                path: path, method: header.uint16(10), compressedSize: sizes.compressed,
                uncompressedSize: sizes.uncompressed, localHeaderOffset: sizes.offset, isEncrypted: flags & 1 != 0
            ))
        }
        return entries
    }

    /// 32-bit fields set to `0xFFFFFFFF` are stored in the ZIP64 extra field (ID 1), in this order.
    private struct Zip64Fields {
        var uncompressed: UInt64
        var compressed: UInt64
        var offset: UInt64

        mutating func apply(extra: Data) {
            var extra = Data(extra)
            while extra.count >= 4 {
                let id = extra.uint16(0)
                let size = Int(extra.uint16(2))
                guard extra.count >= 4 + size else { return }
                if id == 1 {
                    var field = Data(extra[extra.startIndex + 4 ..< extra.startIndex + 4 + size])
                    for keyPath in [\Zip64Fields.uncompressed, \.compressed, \.offset] where self[keyPath: keyPath] == 0xFFFF_FFFF {
                        guard field.count >= 8 else { return }
                        self[keyPath: keyPath] = field.uint64(0)
                        field = Data(field.dropFirst(8))
                    }
                    return
                }
                extra = Data(extra.dropFirst(4 + size))
            }
        }
    }

    // MARK: - Bytes

    private static func read(_ handle: FileHandle, _ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw ZipError.corrupted("unexpected end of file")
        }
        return data
    }

    private static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        for index in stride(from: data.count - 22, through: 0, by: -1) where data.uint32(index) == signature {
            return index
        }
        return nil
    }
}

private extension Data {
    /// Little-endian integers at `offset` from the start of the data.
    func uint16(_ offset: Int) -> UInt16 { little(offset, 2) }
    func uint32(_ offset: Int) -> UInt32 { little(offset, 4) }
    func uint64(_ offset: Int) -> UInt64 { little(offset, 8) }

    private func little<T: FixedWidthInteger>(_ offset: Int, _ size: Int) -> T {
        var value: T = 0
        for byte in 0..<size {
            value |= T(self[startIndex + offset + byte]) << (8 * byte)
        }
        return value
    }
}
