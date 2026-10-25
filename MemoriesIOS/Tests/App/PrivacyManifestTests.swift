import XCTest
@testable import Memories

/// App Store Connect rejects builds whose privacy manifest does not declare the required-reason
/// APIs the app calls (ITMS-91053). This pins the declarations to the APIs used in `Sources/`.
final class PrivacyManifestTests: XCTestCase {
    private func manifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "not bundled")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testNoTrackingAndNoCollectedData() throws {
        let manifest = try manifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    func testDeclaresTheRequiredReasonAPIsTheAppUses() throws {
        let types = try XCTUnwrap(try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: types.compactMap { entry -> (String, [String])? in
            guard let name = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            return (name, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"]) // files in the app container
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryDiskSpace"], ["E174.1"]) // space check before extracting a ZIP
    }
}
