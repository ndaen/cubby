// Adapté de NotchDrop (MIT).
import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController: NSWindowController {
    let shell: NotchShellModel
    private let stripHeight: CGFloat = 300
    private var cancellables: Set<AnyCancellable> = []
    private var courtesyReveal: DispatchWorkItem?

    // Courtoisie envers les apps qui animent l'encoche au déverrouillage
    // (Glance et consorts) : elles dessinent sous nous — `.mainMenu + 3`
    // contre notre `.statusBar + 8` — donc notre coquille fermée leur passe
    // devant pile au moment de leur animation de succès. On s'efface le temps
    // qu'elle se joue. Sans une telle app installée, personne ne voit rien :
    // l'écran vient à peine de réapparaître.
    private static let unlockCourtesy: TimeInterval = 0.8

    init(screen: NSScreen, music: MusicModel, pomo: PomodoroModel) {
        var notch = screen.notchSize
        let inset: CGFloat = (notch == .zero) ? 0 : 4
        let shellModel = NotchShellModel(inset: inset)
        shell = shellModel
        shellModel.resolveOpenTab = { [weak shellModel] in
            guard let shellModel else { return nil }
            return resolvePinTab(shell: shellModel, music: music, pomo: pomo)
        }

        let win = NotchWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: win)

        let root = NotchRootView(shell: shell, music: music, pomo: pomo)
        // fin d'une phase : l'encoche s'ouvre d'elle-même sur le compte à rebours.
        // C'est le shell qui s'abonne au modèle, jamais l'inverse.
        pomo.onPhaseEnded = { [weak shellModel] in
            shellModel?.tab = .pomodoro
            shellModel?.open()
        }

        let host = NSHostingView(rootView: root)
        win.contentView = host

        // bande en haut de l'écran, pleine largeur
        let frame = CGRect(x: screen.frame.minX,
                           y: screen.frame.maxY - stripHeight,
                           width: screen.frame.width,
                           height: stripHeight)
        win.setFrame(frame, display: true)

        // zone de l'encoche (coords écran) pour le hit-test souris
        if notch == .zero { notch = CGSize(width: 180, height: 32) }
        shell.deviceNotchRect = CGRect(
            x: screen.frame.minX + (screen.frame.width - notch.width) / 2,
            y: screen.frame.minY + screen.frame.height - notch.height,
            width: notch.width, height: notch.height
        )
        shell.screenRect = screen.frame

        win.orderFrontRegardless()

        // Le clic "ouvre" est détecté par un moniteur global (NotchShellModel),
        // donc la fenêtre n'a besoin de capter les clics AppKit que pendant
        // qu'elle est visible — sinon elle vole le focus sur toute la bande.
        win.ignoresMouseEvents = true
        shell.$wantsMouseEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak win] wants in
                win?.ignoresMouseEvents = !wants
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.yieldAfterUnlock() }
            .store(in: &cancellables)
    }

    /// Retire la fenêtre le temps qu'une éventuelle animation de
    /// déverrouillage se joue dans l'encoche, puis la remet.
    private func yieldAfterUnlock() {
        courtesyReveal?.cancel()
        shell.close()
        window?.orderOut(nil)

        let reveal = DispatchWorkItem { [weak self] in
            self?.window?.orderFrontRegardless()
            self?.courtesyReveal = nil
        }
        courtesyReveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.unlockCourtesy, execute: reveal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func destroy() {
        courtesyReveal?.cancel()
        courtesyReveal = nil
        window?.close()
        window = nil
    }
}
