import XCTest
import AppKit
@testable import Cubby

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cubby-thumbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    // Écrit un vrai PNG sur disque — Quick Look ne sait rien faire d'un fichier factice.
    private func writePNG(_ name: String) throws -> URL {
        let image = NSImage(size: CGSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    // Un document existant donne une vignette utilisable.
    func testGeneratesAThumbnailForAnExistingFile() async throws {
        let url = try writePNG("carré.png")
        let cache = ThumbnailCache()
        let image = await cache.thumbnail(for: url, side: 44)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    // Le deuxième appel ressort du cache : même instance, aucune régénération.
    func testSecondCallComesFromTheCache() async throws {
        let url = try writePNG("cache.png")
        let cache = ThumbnailCache()
        let first = await cache.thumbnail(for: url, side: 44)
        XCTAssertNil(cache.cached(for: url, side: 96), "une autre taille est une autre entrée")
        let second = await cache.thumbnail(for: url, side: 44)
        XCTAssertTrue(first === second)
        XCTAssertTrue(cache.cached(for: url, side: 44) === first)
    }

    // Rien n'est en cache tant que la vignette n'a pas été demandée.
    func testNothingIsCachedBeforeTheFirstRequest() throws {
        let url = try writePNG("vide.png")
        let cache = ThumbnailCache()
        XCTAssertNil(cache.cached(for: url, side: 44))
    }

    // Un fichier absent retombe sur l'icône système plutôt que de renvoyer rien.
    func testMissingFileFallsBackToTheSystemIcon() async {
        let url = dir.appendingPathComponent("fantôme.pdf")
        let cache = ThumbnailCache()
        let image = await cache.thumbnail(for: url, side: 44)
        XCTAssertGreaterThan(image.size.width, 0)
    }
}
