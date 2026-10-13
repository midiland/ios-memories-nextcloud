import Foundation

/// DSSE envelope (`{ payload, payloadType, signatures: [{ keyid, sig }] }`), the `jsManifest` format
/// of Memories 10 (`memories-manifest.dsse.json`, written by `webpack.manifest-sign-plugin.ts`).
/// The signature covers the pre-auth encoding of the payload, not the payload alone.
struct DSSEEnvelope {
    /// Payload type of the TUF targets signed by Memories.
    static let tufPayloadType = "application/vnd.tuf+json"

    /// Decoded payload bytes, exactly as signed.
    let payload: Data
    let payloadType: String
    /// Base64 signatures, decoded by the verifier (`nil` when an entry has no `sig` string).
    let signatures: [String?]

    /// Parses the envelope object; `nil` if a field is missing or the payload is not base64.
    init?(_ object: [String: Any]) {
        guard let payloadB64 = object["payload"] as? String,
              let payload = Data(base64Encoded: payloadB64),
              let payloadType = object["payloadType"] as? String,
              let signatures = object["signatures"] as? [[String: Any]]
        else { return nil }
        self.payload = payload
        self.payloadType = payloadType
        self.signatures = signatures.map { $0["sig"] as? String }
    }

    /// DSSE pre-auth encoding: `"DSSEv1" SP len(type) SP type SP len(payload) SP payload`.
    static func preAuthEncoding(payloadType: String, payload: Data) -> Data {
        let type = Data(payloadType.utf8)
        var data = Data("DSSEv1 \(type.count) ".utf8)
        data.append(type)
        data.append(Data(" \(payload.count) ".utf8))
        data.append(payload)
        return data
    }
}
