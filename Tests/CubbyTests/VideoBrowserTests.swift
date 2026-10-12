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

    func testBundleIdentifierMapping() {
        XCTAssertEqual(VideoBrowser.from(bundleID: "com.apple.Safari"), .safari)
        XCTAssertEqual(VideoBrowser.from(bundleID: "com.google.Chrome"), .chrome)
        XCTAssertEqual(VideoBrowser.from(bundleID: "org.mozilla.firefox"), .firefox)
        XCTAssertEqual(VideoBrowser.from(bundleID: "company.thebrowser.Browser"), .arc)
        XCTAssertNil(VideoBrowser.from(bundleID: "com.example.unknown"))
        XCTAssertNil(VideoBrowser.from(bundleID: nil))
    }

    func testDefaultChoiceResolvesToSystemBrowser() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "default", systemDefault: .firefox),
                       ["--cookies-from-browser", "firefox"])
    }

    // Arc n'est pas lu par yt-dlp : aucun argument, l'export passe par un fichier de cookies.
    func testArcUsesNoNativeCookieArguments() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "arc"), [])
        XCTAssertEqual(VideoBrowser.resolve("arc"), .arc)
        XCTAssertEqual(VideoBrowser.resolve("default", systemDefault: .arc), .arc)
        XCTAssertNil(VideoBrowser.arc.ytdlpName)
    }

    // Navigateur par défaut non reconnu : on n'envoie rien plutôt qu'un mauvais nom.
    func testDefaultChoiceWithUnsupportedBrowserSendsNothing() {
        XCTAssertEqual(VideoBrowser.cookieArgs(for: "default", systemDefault: nil), [])
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
