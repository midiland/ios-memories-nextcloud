import CryptoKit
import Foundation

/// Vérifie la signature Ed25519 du manifeste JS avant d'exécuter le moindre fichier téléchargé
/// (équivalent de `ManifestVerifier.kt`). CryptoKit implémente Ed25519 standard (RFC 8032).
enum ManifestVerifier {
    /// Clé publique de production (base64, 32 octets), reprise de l'app Android.
    static let productionKey = "aA2fpqrrJHTiCkE9ecQNDR5V1qO7oHppjdJQ7Pj5nhQ="
    /// Clé de développement (graine publique par défaut de `webpack.manifest-sign-plugin.ts`) :
    /// acceptée uniquement en Debug, comme sur Android.
    static let developmentKey = "MIJxGvOr0LMg9Isyfi5S4cHQsP+v4mFzrsmY2AYKOjs="

    static var trustedKeys: [String] {
        #if DEBUG
        return [productionKey, developmentKey]
        #else
        return [productionKey]
        #endif
    }

    /// `true` si la signature du manifeste est valide pour une des clés de confiance.
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
