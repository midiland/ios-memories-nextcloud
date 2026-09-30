import CryptoKit
import Foundation

extension Data {
    /// Lowercase hexadecimal SHA-256 digest.
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
