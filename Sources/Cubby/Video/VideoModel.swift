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
            } catch {
                let message = error.localizedDescription
                state = .failed(YTDLPLine.isCookieAccessDenied(message)
                    ? Loc.shared.s("Safari blocks access to its cookies. Grant Cubby “Full Disk Access” in System Settings → Privacy & Security, or pick another browser.",
                                   "Safari protège ses cookies. Donne l’« Accès complet au disque » à Cubby dans Réglages Système → Confidentialité et sécurité, ou choisis un autre navigateur.")
                    : message)
            }
        }
    }

    func cancel() { VideoEngine.shared.cancel() }

    func reveal(_ file: URL) { NSWorkspace.shared.activateFileViewerSelecting([file]) }

    func reset() { if !busy { state = .idle } }
}
