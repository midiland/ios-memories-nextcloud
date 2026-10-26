import XCTest
@testable import Memories

/// Tests for `NextcloudClient.photos(onDays:)` and `preview(fileid:)`, using `MockURLProtocol`.
final class OnThisDayClientTests: XCTestCase {
    private var client: NextcloudClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        client = NextcloudClient(session: mockSession())
    }

    override func tearDown() {
        client = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - photos(onDays:)

    func testPhotosRequestShape() async throws {
        MockURLProtocol.response = (Data("[]".utf8), 200, [:])
        _ = try await client.photos(onDays: [10, 11], credentials: Fixtures.credentials)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://cloud.example.com/nextcloud/index.php/apps/memories/api/days")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), Fixtures.credentials.basicAuthHeader)
        XCTAssertEqual(request.value(forHTTPHeaderField: "OCS-APIREQUEST"), "true")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), AppConstants.userAgentSuffix)

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: [Int]])
        XCTAssertEqual(json["dayIds"], [10, 11])
    }

    func testPhotosDecodesResponse() async throws {
        let json = #"[{"fileid":7,"dayid":20387,"epoch":"1761436800","w":4000,"h":3000,"size":123,"basename":"a.jpg"}]"#
        MockURLProtocol.response = (Data(json.utf8), 200, [:])
        let photos = try await client.photos(onDays: [20_387], credentials: Fixtures.credentials)
        XCTAssertEqual(photos.map(\.fileid), [7])
        XCTAssertEqual(photos.first?.basename, "a.jpg")
    }

    func testPhotosThrowsNotAuthenticatedOn401() async {
        MockURLProtocol.response = (Data(), 401, [:])
        await assertThrows(AppError.notAuthenticated) {
            _ = try await self.client.photos(onDays: [1], credentials: Fixtures.credentials)
        }
    }

    func testPhotosThrowsOnServerError() async {
        MockURLProtocol.response = (Data(), 500, [:])
        await assertThrows(AppError.unexpectedStatus(500)) {
            _ = try await self.client.photos(onDays: [1], credentials: Fixtures.credentials)
        }
    }

    func testPhotosThrowsOnInvalidJSON() async {
        MockURLProtocol.response = (Data("<html>login</html>".utf8), 200, [:])
        await assertThrows(AppError.invalidResponse) {
            _ = try await self.client.photos(onDays: [1], credentials: Fixtures.credentials)
        }
    }

    func testPhotosMapsNetworkError() async {
        MockURLProtocol.error = URLError(.notConnectedToInternet)
        do {
            _ = try await client.photos(onDays: [1], credentials: Fixtures.credentials)
            XCTFail("Network error must throw")
        } catch AppError.serverUnreachable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - preview

    func testPreviewRequestShapeAndData() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF])
        MockURLProtocol.response = (jpeg, 200, ["Content-Type": "image/jpeg"])
        let data = try await client.preview(fileid: 42, size: 512, credentials: Fixtures.credentials)
        XCTAssertEqual(data, jpeg)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/nextcloud/index.php/apps/memories/api/image/preview/42")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "x" }?.value, "512")
        XCTAssertEqual(query?.first { $0.name == "y" }?.value, "512")
        XCTAssertEqual(query?.first { $0.name == "a" }?.value, "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), Fixtures.credentials.basicAuthHeader)
    }

    func testPreviewThrowsOnNotFound() async {
        MockURLProtocol.response = (Data(), 404, [:])
        await assertThrows(AppError.unexpectedStatus(404)) {
            _ = try await self.client.preview(fileid: 1, size: 256, credentials: Fixtures.credentials)
        }
    }

    func testPreviewThrowsNotAuthenticatedOn401() async {
        MockURLProtocol.response = (Data(), 401, [:])
        await assertThrows(AppError.notAuthenticated) {
            _ = try await self.client.preview(fileid: 1, size: 256, credentials: Fixtures.credentials)
        }
    }

    // MARK: - Helpers

    private func assertThrows(_ expected: AppError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
