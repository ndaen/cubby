import XCTest
@testable import Cubby

final class VideoLinkTests: XCTestCase {
    func testExtractsUrlFromSurroundingText() {
        let url = VideoLink.parse("Regarde ça : https://www.instagram.com/reel/abc123/ trop bien")
        XCTAssertEqual(url?.absoluteString, "https://www.instagram.com/reel/abc123/")
    }

    func testAcceptsBareUrl() {
        XCTAssertEqual(VideoLink.parse("https://x.com/u/status/1")?.host, "x.com")
    }

    func testRejectsTextWithoutLink() {
        XCTAssertNil(VideoLink.parse("pas de lien ici"))
        XCTAssertNil(VideoLink.parse(""))
    }

    func testRejectsNonWebSchemes() {
        XCTAssertNil(VideoLink.parse("file:///etc/passwd"))
        XCTAssertNil(VideoLink.parse("mailto:a@b.fr"))
    }

    func testParsesProgress() {
        XCTAssertEqual(YTDLPLine.parse("[download]  42.5% of ~  10.00MiB at 1.2MiB/s ETA 00:05"), .progress(0.425))
        XCTAssertEqual(YTDLPLine.parse("[download] 100% of 3.20MiB in 00:02"), .progress(1))
    }

    func testParsesFinalPath() {
        XCTAssertEqual(YTDLPLine.parse("CUBBY_DONE:/Users/n/Downloads/clip [id].mp4\n"),
                       .finished("/Users/n/Downloads/clip [id].mp4"))
    }

    func testIgnoresOtherLines() {
        XCTAssertEqual(YTDLPLine.parse("[info] Extracting URL"), .other)
        XCTAssertEqual(YTDLPLine.parse("[download] Destination: a.mp4"), .other)
    }

    func testExtractsLastErrorLine() {
        let err = "WARNING: x\nERROR: [Instagram] abc: Login required\n"
        XCTAssertEqual(YTDLPLine.errorMessage(from: err), "[Instagram] abc: Login required")
        XCTAssertNil(YTDLPLine.errorMessage(from: "WARNING: only"))
    }
}
