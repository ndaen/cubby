import AppKit
import Sparkle

// Mise à jour in-app (Sparkle).
//
// Cubby est un agent (LSUIElement) : rien ne doit surgir en avant-plan sans que
// l'utilisateur l'ait demandé. Les vérifications planifiées sont donc « douces »
// (gentle reminders) — elles allument une pastille dans l'encoche ouverte, et
// c'est tout. La fenêtre de Sparkle n'apparaît que sur un clic explicite.
@MainActor
final class UpdaterModel: NSObject, ObservableObject {
    static let shared = UpdaterModel()

    /// Version disponible au téléchargement, ou nil si l'app est à jour.
    @Published private(set) var availableVersion: String?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // nil hors bundle (`swift run`) : sans SUFeedURL, Sparkle ouvrirait une
    // alerte d'erreur au démarrage. On préfère un dev silencieux.
    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    var isAvailable: Bool { controller != nil }

    /// Vérifie et, le cas échéant, ouvre la fenêtre de mise à jour de Sparkle.
    func check() { controller?.updater.checkForUpdates() }

    /// Vérification automatique en arrière-plan (réglable depuis les préférences).
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

extension UpdaterModel: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // Une vérification planifiée ne prend jamais l'écran : c'est la pastille qui prévient.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool { false }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        // SUAppcastItem/SPUUserUpdateState ne traversent pas les frontières
        // d'isolation : on n'en garde que des valeurs simples.
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        Task { @MainActor [weak self] in
            if userInitiated {
                // agent app : sans ça, la fenêtre de Sparkle naît derrière les autres
                NSApp.activate(ignoringOtherApps: true)
            } else {
                log("mise à jour disponible : \(version)")
                self?.availableVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor [weak self] in self?.availableVersion = nil }
    }
}
