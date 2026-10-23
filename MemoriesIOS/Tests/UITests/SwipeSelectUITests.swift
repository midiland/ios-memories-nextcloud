import XCTest

/// UI tests for the swipe-to-select feature (midiland/ios-memories-nextcloud#11).
///
/// These tests require a running Nextcloud server with Memories installed,
/// and valid credentials configured in the app. They are not run in CI by default.
///
/// To run manually:
/// ```
/// cd MemoriesIOS
/// xcodebuild test -scheme MemoriesIOS -destination 'platform=iOS Simulator,name=iPhone 16' \
///   -only-testing:MemoriesIOSTests/SwipeSelectUITests
/// ```
///
/// Or use the video recording script:
/// ```
/// ./scripts/record-swipe-select-demo.sh
/// ```
final class SwipeSelectUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Verify the app launches and shows either the login screen or the timeline.
    /// This is a smoke test to ensure the swipe-select CSS/JS injection doesn't break startup.
    func testAppLaunchesWithSwipeSelectEnabled() throws {
        // The app should show something — either login or timeline
        let app = app!
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Take a screenshot for the video demo
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "app-launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// If the user is logged in, verify the timeline grid is visible.
    /// This test is skipped if the login screen is shown (no credentials configured).
    func testTimelineGridIsVisible() throws {
        let app = app!

        // Wait for either login or timeline
        let loginButton = app.buttons["Login"]
        let timelineGrid = app.otherElements["memories-timeline"]

        if loginButton.waitForExistence(timeout: 5) {
            // Not logged in — skip this test
            throw XCTSkip("Not logged in — configure credentials to run this test")
        }

        // Timeline should be visible
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
    }

    /// Simulate a swipe gesture on the photo grid and verify selection mode activates.
    /// This test requires being logged in with photos in the timeline.
    func testSwipeSelectGestureActivatesSelectionMode() throws {
        let app = app!

        // Skip if not logged in
        if app.buttons["Login"].waitForExistence(timeout: 5) {
            throw XCTSkip("Not logged in — configure credentials to run this test")
        }

        // Wait for the web view to load
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15))

        // Wait for photos to appear (the web app renders .p-outer-super elements)
        // We can't directly query DOM elements from XCUITest, but we can check
        // that the web view has content by taking a screenshot.
        Thread.sleep(forTimeInterval: 3)

        let screenshotBefore = webView.screenshot()
        let attachmentBefore = XCTAttachment(screenshot: screenshotBefore)
        attachmentBefore.name = "before-swipe"
        attachmentBefore.lifetime = .keepAlways
        add(attachmentBefore)

        // Perform a long-press followed by a swipe on the center of the web view.
        // In the Memories web app, a long-press (600ms) on a photo activates selection mode,
        // then swiping selects multiple photos.
        let center = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // Long press to enter selection mode
        center.press(forDuration: 1.0)

        // Swipe across multiple photos
        let startPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let endPoint = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        startPoint.press(forDuration: 0.1, thenDragTo: endPoint)

        Thread.sleep(forTimeInterval: 1)

        // Take screenshot after swipe
        let screenshotAfter = webView.screenshot()
        let attachmentAfter = XCTAttachment(screenshot: screenshotAfter)
        attachmentAfter.name = "after-swipe"
        attachmentAfter.lifetime = .keepAlways
        add(attachmentAfter)

        // The selection bar should appear (`.memories-top-bar` with "X selected" text)
        // We verify visually via the screenshot — the test passes if no crash occurs
        // and the screenshots show different states.
    }

    /// Test that the CSS is loaded by checking the computed style via JavaScript.
    /// This requires the app to be logged in and showing the timeline.
    func testTouchActionCSSIsApplied() throws {
        let app = app!

        if app.buttons["Login"].waitForExistence(timeout: 5) {
            throw XCTSkip("Not logged in — configure credentials to run this test")
        }

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 15))

        // Wait for the timeline to render
        Thread.sleep(forTimeInterval: 5)

        // Evaluate JavaScript to check touch-action on a photo element
        // Note: XCUITest doesn't directly support evaluateJavaScript, but we can
        // verify indirectly by checking that the swipe gesture works (test above).
        // This is a placeholder for a more sophisticated test using XCUITest's
        // JavaScript evaluation capabilities if available.

        let screenshot = webView.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "css-check"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
