import XCTest
@testable import Cubby

final class MarketMergeTests: XCTestCase {
    private func ext(_ id: String, _ available: Bool = true) -> Extension {
        Extension(id: id, emoji: "x", nameEn: id, nameFr: id, descEn: "", descFr: "", available: available)
    }

    // Extension câblée mais absente du catalogue distant : elle reste visible.
    func testKeepsWiredExtensionMissingFromRemote() {
        let out = MarketModel.merged(remote: [ext("pomodoro")], local: [ext("pomodoro"), ext("video")],
                                     wired: ["pomodoro", "video"])
        XCTAssertEqual(out.map(\.id), ["pomodoro", "video"])
    }

    // Le distant fait foi sur ce qu'il connaît (pas de doublon, pas d'écrasement).
    func testRemoteWinsForKnownIds() {
        let out = MarketModel.merged(remote: [ext("video", false)], local: [ext("video", true)], wired: ["video"])
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].available)
    }

    // Une entrée locale non câblée (« bientôt ») n'est pas ressuscitée.
    func testDoesNotResurrectUnwiredLocalEntries() {
        let out = MarketModel.merged(remote: [ext("pomodoro")], local: [ext("weather", false)], wired: ["pomodoro"])
        XCTAssertEqual(out.map(\.id), ["pomodoro"])
    }
}
