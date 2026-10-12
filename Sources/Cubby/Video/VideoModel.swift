import SwiftUI
import AppKit

@MainActor
final class VideoModel: ObservableObject {
    static let shared = VideoModel()

    enum State: Equatable {
        case idle
        case downloading(Double)
        case done(URL)
        case failed(String)
    }

    // même clé que MarketModel.wiredFlags["video"] : installer l'extension, c'est
    // basculer ce booléen.
    static let installedKey = "cubby.showVideo"

    private static let browserKey = "cubby.video.browser"

    @Published var input = ""
    // Navigateur dont on emprunte les cookies ; "none" = aucun.
    @Published var browser: String = UserDefaults.standard.string(forKey: VideoModel.browserKey) ?? "none" {
        didSet { UserDefaults.standard.set(browser, forKey: Self.browserKey) }
    }
    @Published private(set) var state: State = .idle

    var link: URL? { VideoLink.parse(input) }
    var busy: Bool { if case .downloading = state { true } else { false } }

    // À l'ouverture de l'onglet : si le presse-papiers contient un lien et que le
    // champ est vide, on le préremplit.
    func prefillFromPasteboard() {
        guard input.isEmpty, !busy,
              let text = NSPasteboard.general.string(forType: .string),
              VideoLink.parse(text) != nil else { return }
        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() {
        guard let url = link, !busy else { return }
        state = .downloading(0)
        Task {
            do {
                // La mise à jour passe AVANT le téléchargement, jamais en parallèle : elle
                // réécrit le binaire et partage le même process suivi par cancel().
                await VideoEngine.shared.updateIfStale()
                let file = try await VideoEngine.shared.download(url, cookiesFrom: browser) { [weak self] p in
                    Task { @MainActor in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(p)
                    }
                }
                state = .done(file)
                input = ""
            } catch is CancellationError {
                state = .idle
            } catch let e as CookieExportError {
                state = .failed(Self.message(for: e))
            } catch {
                let message = error.localizedDescription
                state = .failed(YTDLPLine.isCookieAccessDenied(message)
                    ? Loc.shared.s("Safari blocks access to its cookies. Grant Cubby “Full Disk Access” in System Settings → Privacy & Security, or pick another browser.",
                                   "Safari protège ses cookies. Donne l’« Accès complet au disque » à Cubby dans Réglages Système → Confidentialité et sécurité, ou choisis un autre navigateur.")
                    : message)
            }
        }
    }

    private static func message(for e: CookieExportError) -> String {
        let l = Loc.shared
        switch e {
        case .keychainDenied:
            return l.s("Cubby needs access to the “Arc Safe Storage” key in your Keychain to use Arc's login. Try again and click Allow.",
                       "Cubby a besoin de la clé « Arc Safe Storage » du Trousseau pour utiliser la connexion d'Arc. Réessaie et clique sur Autoriser.")
        case .keyNotFound:
            return l.s("No Arc login found in the Keychain. Open Arc once, or pick another browser.",
                       "Aucune clé Arc dans le Trousseau. Ouvre Arc une fois, ou choisis un autre navigateur.")
        case .profileNotFound:
            return l.s("Couldn't find Arc's cookies. Pick another browser.", "Cookies d'Arc introuvables. Choisis un autre navigateur.")
        case .noCookiesForSite:
            return l.s("You're not logged in to this site in Arc (no cookies found in any profile).",
                       "Tu n'es pas connecté à ce site dans Arc (aucun cookie dans aucun profil).")
        case .readFailed:
            return l.s("Couldn't read Arc's cookies.", "Lecture des cookies d'Arc impossible.")
        }
    }

    func cancel() { VideoEngine.shared.cancel() }

    func open(_ file: URL) { NSWorkspace.shared.open(file) }

    func reveal(_ file: URL) { NSWorkspace.shared.activateFileViewerSelecting([file]) }

    func reset() { if !busy { state = .idle } }
}
