import XCTest
@testable import Memories

final class ServerPhotoTests: XCTestCase {
    func testDecodesDayResponse() throws {
        let json = """
        [
          {"fileid": 42, "dayid": 20727, "epoch": "1790807400", "w": 4032, "h": 3024, "size": 2345678,
           "basename": "IMG_0001.HEIC", "buid": "abc", "etag": "e", "mimetype": "image/heic", "liveid": "x"},
          {"fileid": 43, "dayid": 20727, "epoch": 1790807500, "w": 1920, "h": 1080, "size": 99,
           "basename": "clip.mov", "isvideo": 1, "video_duration": 12}
        ]
        """
        let photos = try JSONDecoder().decode([ServerPhoto].self, from: Data(json.utf8))
        XCTAssertEqual(photos.count, 2)
        XCTAssertEqual(photos[0].epoch, 1_790_807_400, "string epoch (database dependent)")
        XCTAssertEqual(photos[0].buid, "abc")
        XCTAssertFalse(photos[0].isVideo)
        XCTAssertEqual(photos[1].epoch, 1_790_807_500)
        XCTAssertNil(photos[1].buid, "only for native callers")
        XCTAssertTrue(photos[1].isVideo)
    }

    func testAuidIsComputedLikeTheFrontend() {
        let photo = ServerPhoto(fileid: 1, dayid: 0, epoch: 1_700_000_000, w: 1, h: 1, size: 12_345,
                                basename: "a.jpg", buid: nil, isVideo: false)
        XCTAssertEqual(photo.auid, "9715f9b5eb4fe45ea2e8996f113a24c4")
    }

    func testMissingRequiredFieldFails() {
        XCTAssertThrowsError(try JSONDecoder().decode(ServerPhoto.self, from: Data(#"{"fileid": 1}"#.utf8)))
    }
}
