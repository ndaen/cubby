import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var shell: NotchShellModel
    @ObservedObject var music: MusicModel
    @ObservedObject var pomo: PomodoroModel
    @ObservedObject private var loc = Loc.shared
    @ObservedObject private var updater = UpdaterModel.shared
    @AppStorage(PomodoroSettings.Keys.installed) private var showPomodoro = false
    @State private var dropTargeting = false

    // onglets visibles dans la barre — une extension non installée reste masquée
    private var visibleTabs: [HubTab] {
        showPomodoro ? HubTab.allCases : HubTab.allCases.filter { $0 != .pomodoro }
    }

    private var notchSize: CGSize {
        switch shell.status {
        case .closed:
            return CGSize(width: max(shell.deviceNotchRect.width, 1),
                          height: max(shell.deviceNotchRect.height, 1))
        case .popping:
            return CGSize(width: shell.deviceNotchRect.width + 36,
                          height: shell.deviceNotchRect.height + 6)
        case .opened:
            return shell.openedSize
        }
    }
    private var topRadius: CGFloat { shell.status == .opened ? 13 : 9 }
    private var bottomRadius: CGFloat {
        if pinActive { return 13 }
        return switch shell.status { case .closed: 9; case .popping: 11; case .opened: 22 }
    }

    // largeur d'une marge latérale (oreille) accueillant une épingle
    private var earW: CGFloat {
        switch pinTab {
        case .pomodoro: return 54                                    // anneau + mm:ss
        default: return min(max(shell.deviceNotchRect.height, 28), 40)
        }
    }
    // onglet épinglé/résolu à afficher sur les flancs (nil = rien)
    private var pinTab: HubTab? { resolvePinTab(shell: shell, music: music, pomo: pomo) }
    private var pinActive: Bool { pinTab != nil && shell.status != .opened }
    // extension noire de chaque côté quand une épingle est active
    private var sideExtra: CGFloat { pinActive ? earW : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            // fond « encoche » en noir pur — s'élargit pour englober les épingles
            // latérales en une seule masse continue (Dynamic Island fusionné)
            NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black)
                .frame(width: notchSize.width + sideExtra * 2 + topRadius * 2, height: notchSize.height)
                .animation(shell.animation, value: pinActive)

            // contenu
            if shell.status == .opened {
                panel
                    .frame(width: shell.openedSize.width, height: shell.openedSize.height, alignment: .top)
                    .transition(.opacity)
            } else {
                // contenu des épingles posé dans les marges noires latérales
                SidePins(shell: shell, music: music, pomo: pomo, pinTab: pinTab,
                         notchWidth: notchSize.width, earW: earW,
                         notchHeight: shell.deviceNotchRect.height)
                    .animation(shell.animation, value: pinActive)

                // zone de dépôt sur l'encoche fermée : ouvre + dépose dans le Bac
                Color.white.opacity(0.001)
                    .frame(width: notchSize.width + 90, height: notchSize.height + 36)
                    .contentShape(Rectangle())
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeting) { providers in
                        deposit(providers); return true
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(shell.animation, value: shell.status)
        .onChange(of: dropTargeting) { _, targeted in
            if targeted { shell.tab = .bac; shell.open() }
        }
        .onChange(of: showPomodoro) { _, on in
            if !on {
                if shell.tab == .pomodoro { shell.tab = .bac }
                if shell.pinnedTab == .pomodoro { shell.pinnedTab = nil }
            }
        }
        .onChange(of: pinActive) { _, _ in updatePinnedContentRect() }
        .onChange(of: earW) { _, _ in updatePinnedContentRect() }
        .onAppear { updatePinnedContentRect() }
        .preferredColorScheme(.dark)
    }

    // zone (coords écran) que la fenêtre doit accepter en survol quand l'encoche est fermée
    private func updatePinnedContentRect() {
        shell.pinnedContentRect = pinActive
            ? shell.deviceNotchRect.insetBy(dx: -earW, dy: 0)
            : .zero
    }

    private func deposit(_ providers: [NSItemProvider]) {
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    FileShelf.shared.add([url.standardizedFileURL])
                    shell.tab = .bac
                    shell.open()
                }
            }
        }
    }

    // Panneau ouvert : barre d'onglets + contenu
    private var panel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(visibleTabs) { t in
                    Button { shell.tab = t } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.icon)
                            Text(loc.s(t.title, t.titleFR))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassBG(Capsule(), active: shell.tab == t, tint: .cubby.opacity(0.28), interactive: true)
                        .foregroundStyle(shell.tab == t ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                // épingle : fixe l'onglet courant sur les flancs de l'encoche fermée
                Button { shell.togglePin(shell.tab) } label: {
                    Image(systemName: shell.pinnedTab == shell.tab ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(45))
                        .padding(7)
                        .glassBG(Circle(), active: shell.pinnedTab == shell.tab, tint: .cubby.opacity(0.28), interactive: true)
                        .foregroundStyle(shell.pinnedTab == shell.tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(loc.s("Pin this tab to the sides of the notch",
                            "Épingler cet onglet sur les flancs de l'encoche"))
                // tout désépingler : repasse en priorité auto (visible seulement si épinglé)
                if shell.pinnedTab != nil {
                    Button { shell.pinnedTab = nil } label: {
                        Image(systemName: "pin.slash")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(7)
                            .glassBG(Circle(), interactive: true)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.s("Unpin all", "Tout désépingler"))
                    .transition(.opacity)
                }
                // mise à jour disponible : une pastille qui prévient, jamais une
                // fenêtre qui s'impose — c'est le clic qui ouvre Sparkle
                if let version = updater.availableVersion {
                    Button { shell.close(); updater.check() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(version)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .glassBG(Capsule(), tint: .cubby.opacity(0.28), interactive: true)
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help(loc.s("Update Cubby to \(version)", "Mettre à jour Cubby vers \(version)"))
                    .transition(.opacity)
                }
                // roue crantée : ferme l'encoche puis ouvre la fenêtre de réglages
                Button { shell.close(); SettingsWindow.shared.show() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(7)
                        .glassBG(Circle(), active: false)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(loc.s("Settings", "Réglages"))
            }
            .animation(.easeOut(duration: 0.18), value: shell.pinnedTab)
            .animation(.easeOut(duration: 0.18), value: updater.availableVersion)

            Group {
                switch shell.tab {
                case .bac: BacTabView()
                case .music: MusicTabView(music: music)
                case .pomodoro: PomodoroTabView(pomo: pomo)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, max(shell.deviceNotchRect.height - 2, 10))
    }
}
