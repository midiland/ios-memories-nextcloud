import Foundation

/// Link from the widget to a photo of the app: `memories-ios://memory?day=<dayid>&file=<fileid>`.
/// Shared with the widget target, which builds it; the app parses it.
struct MemoryDeepLink: Equatable {
    static let scheme = "memories-ios"
    private static let host = "memory"

    /// Day id of the photo, as in the Memories timeline.
    let dayid: Int
    let fileid: Int64

    init(dayid: Int, fileid: Int64) {
        self.dayid = dayid
        self.fileid = fileid
    }

    /// `nil` unless the URL is exactly one of ours with two positive integers: the values end
    /// up in the web view's URL fragment, so nothing else is let through.
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let day = items.first(where: { $0.name == "day" })?.value, let dayid = Int(day), dayid > 0,
              let file = items.first(where: { $0.name == "file" })?.value, let fileid = Int64(file), fileid > 0
        else { return nil }
        self.init(dayid: dayid, fileid: fileid)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "day", value: String(dayid)),
            URLQueryItem(name: "file", value: String(fileid)),
        ]
        return components.url!
    }

    /// Memories' viewer fragment (`#v/<dayid>/<fileid>`): the timeline opens this photo.
    var fragment: String { "v/\(dayid)/\(fileid)" }

    /// The app's entry page, opened on this photo.
    func opening(_ page: URL) -> URL {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? page
    }
}
