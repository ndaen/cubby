import SwiftUI
import AppKit

func log(_ s: String) { FileHandle.standardError.write(Data("[cubby] \(s)\n".utf8)) }

@main
struct CubbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @ObservedObject private var loc = Loc.shared

    var body: some Scene {
        MenuBarExtra("Cubby", systemImage: "eyes") {
            Button(loc.s("Quit", "Quitter")) { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        Services.shared.start()
        rebuild()
    }

    @objc func rebuild() { Services.shared.rebuildWindow() }
}

// Orchestration : modèles + fenêtre encoche.
@MainActor
final class Services {
    static let shared = Services()

    let music = MusicModel()
    private var windowController: NotchWindowController?

    func start() {
        music.start()   // poll continu → alimente l'onglet ET l'épingle latérale
        _ = UpdaterModel.shared   // démarre la vérification de mise à jour en arrière-plan
        log("services démarrés")
    }

    func rebuildWindow() {
        windowController?.destroy()
        let screen = NSScreen.builtin ?? NSScreen.main
        guard let screen else { return }
        windowController = NotchWindowController(screen: screen, music: music, pomo: .shared)
    }
}
