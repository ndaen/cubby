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

    @Published var input = ""
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
                let file = try await VideoEngine.shared.download(url) { [weak self] p in
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
                state = .failed(error.localizedDescription)
            }
        }
        Task { await VideoEngine.shared.updateIfStale() }
    }

    func cancel() { VideoEngine.shared.cancel() }

    func reveal(_ file: URL) { NSWorkspace.shared.activateFileViewerSelecting([file]) }

    func reset() { if !busy { state = .idle } }
}
