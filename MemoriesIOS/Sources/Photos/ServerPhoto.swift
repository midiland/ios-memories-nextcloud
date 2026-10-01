import Foundation

/// A photo of a server day response (`GET …/api/days/{ids}`, `TimelineQueryDays::getDay`),
/// reduced to the fields used for deduplication.
struct ServerPhoto: Decodable, Equatable {
    let fileid: Int64
    let dayid: Int
    let epoch: Int
    let w: Int
    let h: Int
    let size: Int64
    let basename: String
    /// Only returned to native callers (`MemoriesNative` User-Agent).
    let buid: String?
    let isVideo: Bool

    /// Computed by every client, as `utils.applyAuids` does in the frontend.
    var auid: String { PhotoIDs.auid(epoch: epoch, size: size) }

    private enum CodingKeys: String, CodingKey {
        case fileid, dayid, epoch, w, h, size, basename, buid, isvideo
    }

    init(fileid: Int64, dayid: Int, epoch: Int, w: Int, h: Int, size: Int64, basename: String, buid: String?, isVideo: Bool) {
        self.fileid = fileid
        self.dayid = dayid
        self.epoch = epoch
        self.w = w
        self.h = h
        self.size = size
        self.basename = basename
        self.buid = buid
        self.isVideo = isVideo
    }

    /// The server casts most fields to int, but not `epoch`: depending on the database it is a string.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fileid = try c.decodeLenientInt(.fileid)
        dayid = Int(try c.decodeLenientInt(.dayid))
        epoch = Int(try c.decodeLenientInt(.epoch))
        w = Int((try? c.decodeLenientInt(.w)) ?? 0)
        h = Int((try? c.decodeLenientInt(.h)) ?? 0)
        size = (try? c.decodeLenientInt(.size)) ?? 0
        basename = (try? c.decode(String.self, forKey: .basename)) ?? ""
        buid = try? c.decode(String.self, forKey: .buid)
        isVideo = ((try? c.decodeLenientInt(.isvideo)) ?? 0) != 0
    }
}

private extension KeyedDecodingContainer {
    /// Integer sent either as a JSON number or as a numeric string.
    func decodeLenientInt(_ key: Key) throws -> Int64 {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key), let value = Int64(text) { return value }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not an integer")
    }
}
