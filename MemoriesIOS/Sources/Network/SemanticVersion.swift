import Foundation

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
