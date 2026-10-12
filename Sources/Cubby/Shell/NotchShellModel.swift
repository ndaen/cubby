// Machine à états de la coquille — adaptée de NotchDrop (MIT).
import AppKit
import Combine
import SwiftUI

enum HubTab: Int, CaseIterable, Identifiable {
    case bac, music, pomodoro, video
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .bac: return "Files"
        case .music: return "Music"
        case .pomodoro: return "Pomodoro"
        case .video: return "Video"
        }
    }
    var titleFR: String {
        switch self {
        case .bac: return "Fichiers"
        case .music: return "Musique"
        case .pomodoro: return "Pomodoro"
        case .video: return "Vidéo"
        }
    }
    var icon: String {
        switch self {
        case .bac: return "tray.full.fill"
        case .music: return "music.note"
        case .pomodoro: return "timer"
        case .video: return "arrow.down.circle.fill"
        }
    }
}

@MainActor
final class NotchShellModel: ObservableObject {
    enum Status { case closed, popping, opened }

    @Published private(set) var status: Status = .closed
    @Published var tab: HubTab = .bac
    @Published var notchVisible: Bool = true

    // Onglet actuellement mis en avant (épingle/priorité auto) — réglé depuis l'extérieur.
    var resolveOpenTab: (() -> HubTab?)?

    // Onglet épinglé manuellement aux flancs de l'encoche (nil = priorité auto).
    private static let pinKey = "cubby.pinnedTab"
    @Published var pinnedTab: HubTab? = {
        let v = UserDefaults.standard.object(forKey: pinKey) as? Int
        return v.flatMap(HubTab.init(rawValue:))
    }() {
        didSet {
            if let r = pinnedTab?.rawValue {
                UserDefaults.standard.set(r, forKey: Self.pinKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinKey)
            }
        }
    }

    /// Épingle/désépingle l'onglet donné (toggle).
    func togglePin(_ t: HubTab) { pinnedTab = (pinnedTab == t) ? nil : t }

    @Published var deviceNotchRect: CGRect = .zero
    @Published var screenRect: CGRect = .zero
    // zone élargie (encoche + épingles latérales) quand un contenu est affiché à l'état fermé
    // (ex : play/pause musique) — permet à la fenêtre d'accepter les clics dessus.
    @Published var pinnedContentRect: CGRect = .zero
    @Published private(set) var wantsMouseEvents = false

    let inset: CGFloat
    let openedSize = CGSize(width: 540, height: 200)
    let animation: Animation = .interactiveSpring(duration: 0.5, extraBounce: 0.22, blendDuration: 0.125)

    private var cancellables: Set<AnyCancellable> = []
    private var idleTimer: Timer?
    private let idleDelay: TimeInterval = 4   // ferme après 4s souris en dehors

    init(inset: CGFloat) {
        self.inset = inset
        setup()
    }

    var openedRect: CGRect {
        .init(x: screenRect.origin.x + (screenRect.width - openedSize.width) / 2,
              y: screenRect.origin.y + screenRect.height - openedSize.height,
              width: openedSize.width, height: openedSize.height)
    }

    func open() {
        cancelIdleClose()
        if let t = resolveOpenTab?() { tab = t }
        status = .opened
        NSApp.activate(ignoringOtherApps: true)
    }
    func close() { cancelIdleClose(); status = .closed }
    func pop() { status = .popping }

    private func scheduleIdleClose() {
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
    private func cancelIdleClose() { idleTimer?.invalidate(); idleTimer = nil }

    private func hit(_ p: NSPoint) -> Bool {
        deviceNotchRect.insetBy(dx: inset, dy: inset).contains(p)
    }

    // la fenêtre doit accepter les vrais clics AppKit dès que la souris survole
    // l'encoche ouverte/en pop, ou la zone épingles quand quelque chose y est affiché.
    private func updateWantsMouseEvents(_ p: NSPoint) {
        switch status {
        case .opened, .popping:
            wantsMouseEvents = true
        case .closed:
            wantsMouseEvents = pinnedContentRect != .zero && pinnedContentRect.contains(p)
        }
    }

    private func setup() {
        let events = EventMonitors.shared

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let m = NSEvent.mouseLocation
                switch status {
                case .opened:
                    if !openedRect.contains(m) { close() }
                case .closed, .popping:
                    if hit(m) { open() }
                }
            }
            .store(in: &cancellables)

        events.mouseLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let m = NSEvent.mouseLocation
                switch status {
                case .closed:
                    if hit(m) { pop() }
                case .popping:
                    if !hit(m) { close() }
                case .opened:
                    // ferme après un délai si la souris reste hors du panneau
                    if openedRect.insetBy(dx: -24, dy: -24).contains(m) {
                        cancelIdleClose()
                    } else {
                        scheduleIdleClose()
                    }
                }
                updateWantsMouseEvents(m)
            }
            .store(in: &cancellables)

        // ouvre au survol pendant un glisser de fichier (drag&drop arrivant de l'extérieur)
        events.mouseDraggingFile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if status != .opened, hit(NSEvent.mouseLocation) { open() }
            }
            .store(in: &cancellables)

        $status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateWantsMouseEvents(NSEvent.mouseLocation) }
            .store(in: &cancellables)

        $status
            .filter { $0 != .closed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in withAnimation { self?.notchVisible = true } }
            .store(in: &cancellables)

        $status
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .filter { $0 == .closed }
            .sink { [weak self] _ in withAnimation { self?.notchVisible = false } }
            .store(in: &cancellables)
    }
}
