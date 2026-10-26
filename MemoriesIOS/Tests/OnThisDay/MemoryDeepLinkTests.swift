import XCTest
@testable import Memories

final class MemoryDeepLinkTests: XCTestCase {
    func testRoundTrip() throws {
        let link = MemoryDeepLink(dayid: 20_387, fileid: 123_456)
        XCTAssertEqual(MemoryDeepLink(url: link.url), link)
    }

    func testURLShape() {
        let url = MemoryDeepLink(dayid: 20_387, fileid: 9).url
        XCTAssertEqual(url.absoluteString, "memories-ios://memory?day=20387&file=9")
    }

    func testFragmentIsTheViewerFragment() {
        XCTAssertEqual(MemoryDeepLink(dayid: 20_387, fileid: 9).fragment, "v/20387/9")
    }

    func testOpeningAddsTheFragmentToTheEntryPage() {
        let page = URL(string: "http://127.0.0.1:62079/index.php/apps/memories/")!
        let opened = MemoryDeepLink(dayid: 5, fileid: 7).opening(page)
        XCTAssertEqual(opened.absoluteString, "http://127.0.0.1:62079/index.php/apps/memories/#v/5/7")
    }

    func testOpeningReplacesAnExistingFragment() {
        let page = URL(string: "http://127.0.0.1:62079/app/#old")!
        XCTAssertEqual(MemoryDeepLink(dayid: 5, fileid: 7).opening(page).fragment, "v/5/7")
    }

    func testRejectsOtherSchemesAndHosts() {
        XCTAssertNil(MemoryDeepLink(url: URL(string: "https://memory?day=1&file=2")!))
        XCTAssertNil(MemoryDeepLink(url: URL(string: "memories-ios://other?day=1&file=2")!))
    }

    func testRejectsMissingOrInvalidValues() {
        for text in [
            "memories-ios://memory", "memories-ios://memory?day=1", "memories-ios://memory?file=2",
            "memories-ios://memory?day=abc&file=2", "memories-ios://memory?day=1&file=x/../y",
            "memories-ios://memory?day=0&file=2", "memories-ios://memory?day=1&file=-3",
            "memories-ios://memory?day=1&file=2%26e/1", "memories-ios://memory?day=1.5&file=2",
        ] {
            XCTAssertNil(MemoryDeepLink(url: URL(string: text)!), text)
        }
    }

    func testRouterKeepsALinkUntilItIsTaken() async {
        let router = await DeepLinkRouter()
        let link = MemoryDeepLink(dayid: 5, fileid: 7)
        await router.handle(link.url)
        let first = await router.takeMemory()
        let second = await router.takeMemory()
        XCTAssertEqual(first, link)
        XCTAssertNil(second)
    }

    func testRouterIgnoresForeignURLs() async {
        let router = await DeepLinkRouter()
        await router.handle(URL(string: "https://example.com")!)
        let taken = await router.takeMemory()
        XCTAssertNil(taken)
    }
}
