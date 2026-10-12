import XCTest
@testable import Cubby

final class VideoBrowserTests: XCTestCase {
    func testCookieArgsForKnownBrowser() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "safari"), ["--cookies-from-browser", "safari"])
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "firefox"), ["--cookies-from-browser", "firefox"])
    }

    func testNoCookiesWhenUnsetOrNone() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: nil), [])
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "none"), [])
        XCTAssertEqual(VideoBrowser.cookieArgs(for: ""), [])
    }

    // Une valeur inconnue (ou hostile) ne doit jamais atteindre la ligne de commande.
    func testUnknownIdentifierNeverBecomesAnArgument() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "safari --exec rm"), [])
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "netscape"), [])
    }

    func testInstalledDetectionUsesAppBundles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Applications/Google Chrome.app"),
                                                withIntermediateDirectories: true)
        final class HomeFM: FileManager, @unchecked Sendable {
            var home: URL!
            override var homeDirectoryForCurrentUser: URL { home }
        }
        let fm = HomeFM(); fm.home = tmp
        XCTAssertTrue(VideoBrowser.installed(fileManager: fm).contains(.chrome))
    }
}
