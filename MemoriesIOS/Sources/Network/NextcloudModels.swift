import Foundation

/// Response of `GET …/apps/memories/api/describe` (see `OtherController::describeApi`).
struct DescribeResponse: Decodable {
    let version: String
    /// Absolute root of the Memories app, e.g. `https://cloud/index.php/apps/memories/`.
    let baseUrl: String
    /// Login Flow v2 initialization endpoint (`/index.php/login/v2`).
    let loginFlowUrl: String
    /// Authenticated user; `nil` if the request is anonymous or the credentials are invalid.
    let uid: String?
}

/// Response of `POST /index.php/login/v2`.
struct LoginFlowInit: Decodable {
    struct Poll: Decodable {
        let token: String
        let endpoint: URL
    }

    let poll: Poll
    /// Login page to open in the browser.
    let login: URL
}

/// Login Flow v2 polling response once the login is approved.
struct LoginFlowResult: Decodable {
    let server: String
    let loginName: String
    let appPassword: String
}

/// Compares versions like `9.0.0-rc.1` (a pre-release is lower than the final release).
struct SemanticVersion: Comparable {
    let numbers: [Int]
    let preRelease: String?

    init(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        numbers = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        preRelease = parts.count > 1 ? parts[1] : nil
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<count {
            let l = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let r = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if l != r { return l < r }
        }
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        case let (l?, r?): return l.compare(r, options: .numeric) == .orderedAscending
        }
    }
}
