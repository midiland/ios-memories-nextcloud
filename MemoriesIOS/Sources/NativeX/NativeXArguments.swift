import Foundation

/// Typed access to a JS message's arguments (JS `null` → `NSNull`).
struct NativeXArguments {
    private let values: [Any]

    init(_ values: [Any]) { self.values = values }

    func string(_ index: Int) -> String? {
        index < values.count ? values[index] as? String : nil
    }

    func bool(_ index: Int) -> Bool {
        index < values.count ? (values[index] as? Bool) ?? false : false
    }
}
