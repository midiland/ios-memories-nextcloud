import Foundation

/// TUF targets metadata carried by the DSSE payload of Memories 10:
/// `{ _type: "targets", version, expires, targets: { name: { length, hashes: { sha256 }, custom: { href } } } }`.
/// `version` is the build time (newer builds have a higher version), `expires` an ISO 8601 date.
struct TUFTargets {
    struct Target {
        let name: String
        let length: Int
        let sha256: String
        let href: String
    }

    let version: Int
    let expires: Date
    let targets: [Target]

    /// Parses the payload; `nil` unless it is a targets document with a version and an expiry date.
    /// Targets without a length, SHA-256 or `href` are skipped.
    init?(payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["_type"] as? String == "targets",
              let version = (object["version"] as? NSNumber)?.intValue,
              let expiresText = object["expires"] as? String,
              let expires = Self.parseDate(expiresText),
              let targets = object["targets"] as? [String: Any]
        else { return nil }
        self.version = version
        self.expires = expires
        self.targets = targets.compactMap { name, value in
            guard let entry = value as? [String: Any],
                  let length = (entry["length"] as? NSNumber)?.intValue,
                  let sha256 = (entry["hashes"] as? [String: Any])?["sha256"] as? String, !sha256.isEmpty,
                  let href = (entry["custom"] as? [String: Any])?["href"] as? String
            else { return nil }
            return Target(name: name, length: length, sha256: sha256, href: href)
        }
    }

    /// `2029-10-12T05:20:17Z`, with or without fractional seconds.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
    }
}
