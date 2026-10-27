import AppKit
import ApplicationServices

// Les oreilles de l'encoche (épingles latérales) débordent sur la barre de menus.
// On ne les affiche en permanence que si elles ne recouvrent rien.
enum MenuBarLayout {
    // marge de sécurité entre une oreille et le premier élément voisin
    static let gap: CGFloat = 4

    /// - notch : étendue horizontale de l'encoche (x global)
    /// - ear : débord d'une oreille de chaque côté de l'encoche
    /// - menus : titres de menus de l'app au premier plan
    /// - extras : icônes de statut
    static func earsBlocked(notch: ClosedRange<CGFloat>, ear: CGFloat,
                            menus: [ClosedRange<CGFloat>], extras: [ClosedRange<CGFloat>]) -> Bool {
        let reach = ear + gap
        let left = (notch.lowerBound - reach)...notch.lowerBound
        let right = notch.upperBound...(notch.upperBound + reach)
        // sur un écran à encoche, macOS range à gauche de l'encoche les icônes
        // qui ne tiennent plus : elles sont masquées, donc ne gênent rien
        let shown = extras.filter { $0.lowerBound >= notch.upperBound }
        return (menus + shown).contains { item in
            [left, right].contains { item.lowerBound < $0.upperBound && item.upperBound > $0.lowerBound }
        }
    }
}

// Relève, via l'API Accessibilité, ce qu'affiche la barre de menus de l'écran
// de l'encoche. Sans autorisation, `items` reste nil : on ne sait pas, donc
// les oreilles ne s'affichent qu'au survol.
@MainActor
final class MenuBarProbe: ObservableObject {
    static let shared = MenuBarProbe()

    struct Items: Equatable {
        var menus: [ClosedRange<CGFloat>]
        var extras: [ClosedRange<CGFloat>]
    }

    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var items: Items?

    /// Vrai tant qu'une épingle voudrait s'afficher : la sonde ne tourne qu'à ce moment-là.
    var active = false {
        didSet { if active, !oldValue { refresh() } }
    }

    private var screen: NSScreen?
    private var scanning = false
    private var timer: Timer?
    private var activation: NSObjectProtocol?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in MenuBarProbe.shared.refresh() }
        }
        // les menus changent avec l'app au premier plan : on relit sans attendre
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in MenuBarProbe.shared.refresh() }
        }
    }

    func attach(_ screen: NSScreen) {
        self.screen = screen
        refresh()
    }

    /// Ouvre la demande d'autorisation système (Réglages › Accessibilité).
    func requestAccess() {
        // valeur de kAXTrustedCheckOptionPrompt (globale C non isolée en Swift 6)
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        guard trusted else { items = nil; return }
        guard active, !scanning, let screen, let primary = NSScreen.screens.first else { return }

        // l'API Accessibilité compte y depuis le haut de l'écran principal
        let top = primary.frame.maxY - screen.frame.maxY
        let band = top...(top + max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map(\.processIdentifier)

        scanning = true
        Task.detached(priority: .utility) {
            let found = Self.scan(band: band, front: front, pids: pids)
            await MainActor.run {
                let probe = MenuBarProbe.shared
                probe.scanning = false
                if probe.items != found { probe.items = found }
            }
        }
    }

    nonisolated private static func scan(band: ClosedRange<CGFloat>, front: pid_t?, pids: [pid_t]) -> Items {
        let menus = front.map { children(of: $0, bar: kAXMenuBarAttribute, band: band) } ?? []
        let extras = pids.flatMap { children(of: $0, bar: "AXExtrasMenuBar", band: band) }
        return Items(menus: menus, extras: extras)
    }

    nonisolated private static func children(of pid: pid_t, bar: String,
                                             band: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        let app = AXUIElementCreateApplication(pid)
        // une app figée ne doit pas bloquer la sonde (6 s par défaut)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let menuBar: AXUIElement = value(app, bar),
              let kids: [AXUIElement] = value(menuBar, kAXChildrenAttribute) else { return [] }
        return kids.compactMap { el in
            guard let p: AXValue = value(el, kAXPositionAttribute),
                  let s: AXValue = value(el, kAXSizeAttribute) else { return nil }
            var origin = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(p, .cgPoint, &origin)
            AXValueGetValue(s, .cgSize, &size)
            guard size.width > 0, band.contains(origin.y + size.height / 2) else { return nil }
            return origin.x...(origin.x + size.width)
        }
    }

    nonisolated private static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? T
    }
}
