import Photos
import XCTest
@testable import Memories

final class DeviceSetupRuleTests: XCTestCase {
    func testOffersWhenNeverAsked() {
        XCTAssertTrue(DeviceSetupRule.shouldOffer(alreadyOffered: false, isEnabled: false, status: .notDetermined))
    }

    func testOffersOnlyOnce() {
        XCTAssertFalse(DeviceSetupRule.shouldOffer(alreadyOffered: true, isEnabled: false, status: .notDetermined))
    }

    func testSkipsWhenAlreadyEnabled() {
        XCTAssertFalse(DeviceSetupRule.shouldOffer(alreadyOffered: false, isEnabled: true, status: .notDetermined))
    }

    func testSkipsWhenPromptAlreadyAnswered() {
        for status: PHAuthorizationStatus in [.authorized, .limited, .denied, .restricted] {
            XCTAssertFalse(DeviceSetupRule.shouldOffer(alreadyOffered: false, isEnabled: false, status: status))
        }
    }
}
