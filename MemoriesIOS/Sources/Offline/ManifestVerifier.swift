import CryptoKit
import Foundation

/// Verifies the JS manifest's Ed25519 signature before running any downloaded file
/// (equivalent of `ManifestVerifier.kt`). CryptoKit implements standard Ed25519 (RFC 8032).
enum ManifestVerifier {
    /// Production public key (base64, 32 bytes), taken from the Android app.
    static let productionKey = "aA2fpqrrJHTiCkE9ecQNDR5V1qO7oHppjdJQ7Pj5nhQ="
    /// Development key (default public seed of `webpack.manifest-sign-plugin.ts`):
    /// accepted in Debug builds only, as on Android.
    static let developmentKey = "MIJxGvOr0LMg9Isyfi5S4cHQsP+v4mFzrsmY2AYKOjs="

    static var trustedKeys: [String] {
        #if DEBUG
        return [productionKey, developmentKey]
        #else
        return [productionKey]
        #endif
    }

    /// `true` if the manifest signature is valid for one of the trusted keys.
    static func verify(_ manifest: AssetManifest) -> Bool {
        guard let document = manifest.signatureDocument,
              let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any],
              let signatureB64 = object["curve25519"] as? String,
              let signature = Data(base64Encoded: signatureB64, options: .ignoreUnknownCharacters),
              signature.count == 64
        else { return false }

        return trustedKeys.contains { keyB64 in
            guard let raw = Data(base64Encoded: keyB64),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            else { return false }
            return key.isValidSignature(signature, for: manifest.jsManifest)
        }
    }
}
