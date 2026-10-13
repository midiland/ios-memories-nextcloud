import CryptoKit
import XCTest
@testable import Memories

/// Memories 10 manifests: DSSE envelope over TUF targets.
final class DSSEManifestTests: XCTestCase {
    private let beforeExpiry = ISO8601DateFormatter().date(from: "2026-10-13T00:00:00Z")!

    // MARK: - Real release

    func testAcceptsTheMemories10ReleaseManifest() throws {
        let manifest = try AssetManifest(raw: Fixtures.envelopeDescribe(Fixtures.releaseEnvelope()))
        XCTAssertTrue(ManifestVerifier.verify(manifest, now: beforeExpiry), "signed with the production key")
        XCTAssertEqual(manifest.targets?.version, 1_791_782_417)
        XCTAssertEqual(manifest.js.count, 63)
        let main = try XCTUnwrap(manifest.js.first { $0.name == AssetManifest.entryJS })
        XCTAssertTrue(main.href.hasPrefix("/apps/memories/js/memories-main.js?v=\(main.sha256)"))
        XCTAssertNotNil(main.length)
    }

    func testRejectsTheReleaseManifestOnceExpired() throws {
        let manifest = try AssetManifest(raw: Fixtures.envelopeDescribe(Fixtures.releaseEnvelope()))
        let afterExpiry = ISO8601DateFormatter().date(from: "2029-10-12T05:20:18Z")!
        XCTAssertFalse(ManifestVerifier.verify(manifest, now: afterExpiry))
    }

    func testRejectsTheReleaseManifestWithAModifiedPayload() throws {
        var envelope = try XCTUnwrap(Fixtures.releaseEnvelope() as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope["payload"] as? String)))
        let text = try XCTUnwrap(String(data: payload, encoding: .utf8))
        envelope["payload"] = Data(text.replacingOccurrences(of: "/apps/memories/js/memories-main.js", with: "/evil.js").utf8)
            .base64EncodedString()
        let manifest = try AssetManifest(raw: Fixtures.envelopeDescribe(envelope))
        XCTAssertFalse(ManifestVerifier.verify(manifest, now: beforeExpiry))
    }

    // MARK: - Parsing

    func testParsesTargets() throws {
        let manifest = try AssetManifest(raw: Fixtures.dsseDescribe())
        // Targets without a length are ignored.
        XCTAssertEqual(manifest.js.map(\.name), ["memories-l10n.js", "memories-main.js"])
        XCTAssertEqual(manifest.js.last?.sha256, "aa")
        XCTAssertEqual(manifest.js.last?.length, 12)
        XCTAssertEqual(manifest.js.last?.href, "/nextcloud/apps/memories/js/memories-main.js?v=aa")
        XCTAssertEqual(manifest.css.map(\.name), ["00_server.css", "01_memories-main.css"])
    }

    func testKeyChangesWithThePayload() throws {
        let a = try AssetManifest(raw: Fixtures.dsseDescribe())
        let b = try AssetManifest(raw: Fixtures.dsseDescribe(version: 2_000_000_000))
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertNotEqual(a.key, try AssetManifest(raw: Fixtures.describe()).key)
    }

    func testMalformedEnvelopesThrow() throws {
        let bad: [Any] = [
            ["payloadType": DSSEEnvelope.tufPayloadType, "signatures": []],
            ["payload": "not base64!", "payloadType": DSSEEnvelope.tufPayloadType, "signatures": []],
            ["payload": Data("{}".utf8).base64EncodedString(), "payloadType": DSSEEnvelope.tufPayloadType, "signatures": []],
            42,
        ]
        for envelope in bad {
            XCTAssertThrowsError(try AssetManifest(raw: Fixtures.envelopeDescribe(envelope))) { error in
                guard case OfflineError.noManifest = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testPreAuthEncoding() {
        let pae = DSSEEnvelope.preAuthEncoding(payloadType: "http://example.com/HelloWorld", payload: Data("hello world".utf8))
        // Test vector of the DSSE specification (protocol.md).
        XCTAssertEqual(String(data: pae, encoding: .utf8), "DSSEv1 29 http://example.com/HelloWorld 11 hello world")
    }

    // MARK: - Verification

    #if DEBUG
    func testAcceptsEnvelopeSignedWithDevelopmentKey() throws {
        XCTAssertTrue(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.dsseDescribe())))
    }
    #endif

    func testRejectsUnknownKey() throws {
        let seed = Curve25519.Signing.PrivateKey().rawRepresentation
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.dsseDescribe(signingSeed: seed))))
    }

    func testRejectsOtherPayloadType() throws {
        let raw = try Fixtures.dsseDescribe(payloadType: "application/json")
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: raw)))
    }

    func testRequiresExactlyOneSignature() throws {
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.dsseDescribe(signatures: 0))))
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.dsseDescribe(signatures: 2))))
    }

    func testRejectsExpiredTargets() throws {
        let raw = try Fixtures.dsseDescribe(expires: "2020-01-01T00:00:00Z")
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: raw)))
    }

    func testRejectsSignatureOverThePayloadAlone() throws {
        // A signature of the raw payload (no pre-auth encoding) must not verify.
        var envelope = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: Fixtures.dsseDescribe()) as? [String: Any])?["jsManifest"] as? [String: Any]
        )
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(envelope["payload"] as? String)))
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Fixtures.developmentSeed)
        envelope["signatures"] = [["sig": try key.signature(for: payload).base64EncodedString()]]
        XCTAssertFalse(ManifestVerifier.verify(try AssetManifest(raw: Fixtures.envelopeDescribe(envelope))))
    }
}
