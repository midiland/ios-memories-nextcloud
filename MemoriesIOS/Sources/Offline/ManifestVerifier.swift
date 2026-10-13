import CryptoKit
import Foundation

/// Verifies the JS manifest's Ed25519 signature before running any downloaded file
/// (equivalent of `ManifestVerifier.kt`), in both formats of `AssetManifest.Signed`. CryptoKit implements standard Ed25519 (RFC 8032).
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

    /// `true` if the manifest is signed by one of the trusted keys and, for Memories 10,
    /// its TUF targets have not expired at `now`.
    static func verify(_ manifest: AssetManifest, now: Date = Date()) -> Bool {
        switch manifest.signed {
        case .legacy(let bytes, let signatureDocument):
            return verifyLegacy(bytes, signatureDocument: signatureDocument)
        case .dsse(let envelope, let targets):
            return verifyDSSE(envelope) && targets.expires > now
        }
    }

    /// Memories 9: `jsManifestSig` = `{ "curve25519": <base64 signature of the manifest bytes> }`.
    private static func verifyLegacy(_ bytes: Data, signatureDocument: Data?) -> Bool {
        guard let document = signatureDocument,
              let object = try? JSONSerialization.jsonObject(with: document) as? [String: Any],
              let signatureB64 = object["curve25519"] as? String,
              let signature = Data(base64Encoded: signatureB64, options: .ignoreUnknownCharacters)
        else { return false }
        return isTrusted(signature, for: bytes)
    }

    /// Memories 10: exactly one signature, over the DSSE pre-auth encoding of the TUF payload
    /// (same rules as `ManifestVerifier.kt` on Android).
    private static func verifyDSSE(_ envelope: DSSEEnvelope) -> Bool {
        guard envelope.payloadType == DSSEEnvelope.tufPayloadType,
              envelope.signatures.count == 1,
              let signatureB64 = envelope.signatures[0],
              let signature = Data(base64Encoded: signatureB64)
        else { return false }
        let message = DSSEEnvelope.preAuthEncoding(payloadType: envelope.payloadType, payload: envelope.payload)
        return isTrusted(signature, for: message)
    }

    private static func isTrusted(_ signature: Data, for message: Data) -> Bool {
        guard signature.count == 64 else { return false }
        return trustedKeys.contains { keyB64 in
            guard let raw = Data(base64Encoded: keyB64),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            else { return false }
            return key.isValidSignature(signature, for: message)
        }
    }
}
