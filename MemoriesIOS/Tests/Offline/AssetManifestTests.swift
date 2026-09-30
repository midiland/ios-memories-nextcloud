import XCTest
@testable import Memories

final class AssetManifestTests: XCTestCase {
    func testParsesJSAssetsSortedAndFiltered() throws {
        let manifest = try AssetManifest(raw: Fixtures.describe())
        // `.map` files and entries without a hash are ignored.
        XCTAssertEqual(manifest.js.map(\.name), ["memories-l10n.js", "memories-main.js"])
        XCTAssertEqual(manifest.js.last?.sha256, "aa")
        XCTAssertEqual(manifest.js.last?.href, "/nextcloud/apps/memories/js/memories-main.js")
        XCTAssertEqual(manifest.describe.uid, "alice")
    }

    func testParsesCSSWithStableNamesAndAttributes() throws {
        let manifest = try AssetManifest(raw: Fixtures.describe())
        XCTAssertEqual(manifest.css.map(\.name), ["00_server.css", "01_memories-main.css"])
        XCTAssertEqual(manifest.css[0].attributes["media"], "screen")
        XCTAssertNil(manifest.css[1].attributes["nonce"], "null attributes are dropped")
    }

    func testKeyDependsOnContentOnly() throws {
        let a = try AssetManifest(raw: Fixtures.describe())
        let b = try AssetManifest(raw: Fixtures.describe(signingSeed: nil, uid: "bob"))
        XCTAssertEqual(a.key, b.key)
        XCTAssertEqual(a.key.count, 64)

        var css = Fixtures.cssManifest
        css[0]["href"] = "/nextcloud/core/css/server.css?v=2"
        XCTAssertNotEqual(try AssetManifest(raw: Fixtures.describe(cssManifest: css)).key, a.key)
    }

    func testMissingManifestThrows() throws {
        let raw = try JSONSerialization.data(withJSONObject: [
            "version": "9.1.0", "baseUrl": "https://x/", "loginFlowUrl": "https://x/login/v2",
        ])
        XCTAssertThrowsError(try AssetManifest(raw: raw)) { error in
            guard case OfflineError.noManifest = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try AssetManifest(raw: Data("not json".utf8)))
    }

    func testCSSNameStripsQueryAndPads() {
        XCTAssertEqual(AssetManifest.cssName(index: 3, href: "/core/css/server.css?v=abc"), "03_server.css")
        XCTAssertEqual(AssetManifest.cssName(index: 12, href: "style.css"), "12_style.css")
    }

    func testSHA256Hex() {
        XCTAssertEqual(Data("abc".utf8).sha256Hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
