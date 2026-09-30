import XCTest
@testable import Memories

final class CSSPathRewriterTests: XCTestCase {
    private func rewrite(_ css: String, href: String = "/core/css/server.css?v=1") -> String {
        String(data: CSSPathRewriter.rewrite(Data(css.utf8), originalHref: href), encoding: .utf8)!
    }

    func testResolvesRelativeImport() {
        XCTAssertEqual(rewrite("@import '../../dist/icons.css';"), "@import '/dist/icons.css';")
        XCTAssertEqual(rewrite(#"@import "./fonts.css";"#), #"@import "/core/css/fonts.css";"#)
    }

    func testResolvesRelativeURLKeepingQueryAndFragment() {
        XCTAssertEqual(rewrite("a{background:url(../img/x.svg?v=2#icon)}"), "a{background:url(/core/img/x.svg?v=2#icon)}")
        XCTAssertEqual(rewrite(#"a{background:url("logo.png")}"#), #"a{background:url("/core/css/logo.png")}"#)
    }

    func testLeavesAbsoluteAndSpecialReferences() {
        let css = """
        a{background:url(data:image/png;base64,AAAA)}
        b{background:url(https://cdn.example.org/x.png)}
        c{background:url(//cdn.example.org/y.png)}
        d{background:url(/core/img/z.png)}
        e{filter:url(#shadow)}
        """
        XCTAssertEqual(rewrite(css), css)
    }

    func testResolvesAgainstSubfolderWebRoot() {
        XCTAssertEqual(
            rewrite("@import '../../dist/icons.css';", href: "/nextcloud/core/css/server.css"),
            "@import '/nextcloud/dist/icons.css';"
        )
    }

    func testNonUTF8DataIsReturnedUnchanged() {
        let data = Data([0xff, 0xfe, 0xfd])
        XCTAssertEqual(CSSPathRewriter.rewrite(data, originalHref: "/core/css/a.css"), data)
    }
}
