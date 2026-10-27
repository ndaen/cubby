import XCTest
@testable import Cubby

// Cotes relevées sur un MacBook Pro 14" : encoche de 663.5 à 848.5,
// oreille musique = 32 + 9 d'arrondi.
final class MenuBarLayoutTests: XCTestCase {
    private let notch: ClosedRange<CGFloat> = 663.5...848.5
    private let ear: CGFloat = 41

    private func blocked(menus: [ClosedRange<CGFloat>] = [],
                         extras: [ClosedRange<CGFloat>] = []) -> Bool {
        MenuBarLayout.earsBlocked(notch: notch, ear: ear, menus: menus, extras: extras)
    }

    func testFreeMenuBarKeepsEars() {
        XCTAssertFalse(blocked(menus: [10...44, 43...132, 137...179],
                               extras: [1105...1129, 1143...1173]))
    }

    func testMenuPushedRightOfNotchBlocksEars() {
        // WebStorm : « Window » renvoyé par macOS juste après l'encoche
        XCTAssertTrue(blocked(menus: [615...654, 858...927]))
    }

    func testLongMenuNextToNotchBlocksEars() {
        XCTAssertTrue(blocked(menus: [600...640]))
    }

    func testStatusIconNextToNotchBlocksEars() {
        XCTAssertTrue(blocked(extras: [880...904]))
    }

    func testOverflowIconsLeftOfNotchAreIgnored() {
        // icônes masquées par macOS faute de place : rangées à gauche de l'encoche
        XCTAssertFalse(blocked(extras: [574...598, 640...660]))
    }

    func testItemJustOutsideReachDoesNotBlock() {
        // portée d'une oreille = 41 + 4 de marge
        XCTAssertFalse(blocked(menus: [600...618.5], extras: [893.5...920]))
        XCTAssertTrue(blocked(extras: [893...920]))
    }
}
