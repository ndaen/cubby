import SwiftUI
import AppKit

// Racine de la fenêtre de réglages : 3 onglets natifs.
struct SettingsRoot: View {
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(loc.s("General", "Général"), systemImage: "gearshape") }
            MarketplaceView()
                .tabItem { Label(loc.s("Marketplace", "Marché"), systemImage: "bag.fill") }
            DevelopView()
                .tabItem { Label(loc.s("Develop", "Développer"), systemImage: "hammer.fill") }
        }
        .frame(width: 500, height: 580)
        .tint(.cubby)
    }
}

// ── Général : langue ──────────────────────────────────────────────
private struct GeneralSettings: View {
    @ObservedObject private var loc = Loc.shared
    @ObservedObject private var updater = UpdaterModel.shared
    @AppStorage(PomodoroSettings.Keys.installed) private var showPomodoro = false

    var body: some View {
        Form {
            Section(loc.s("Language", "Langue")) {
                Picker(selection: $loc.lang) {
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                } label: { Text(loc.s("Interface language", "Langue de l'interface")) }
                .pickerStyle(.segmented)
            }
            Section(loc.s("Updates", "Mises à jour")) {
                LabeledContent(loc.s("Installed version", "Version installée"),
                               value: updater.currentVersion)
                Toggle(loc.s("Check automatically", "Vérifier automatiquement"),
                       isOn: Binding(get: { updater.automaticallyChecks },
                                     set: { updater.automaticallyChecks = $0 }))
                HStack {
                    Button(loc.s("Check for updates…", "Rechercher les mises à jour…")) {
                        updater.check()
                    }
                    if let version = updater.availableVersion {
                        Text(loc.s("Cubby \(version) is available",
                                   "Cubby \(version) est disponible"))
                            .font(.caption).foregroundStyle(.tint)
                    }
                }
            }
            // sans bundle (swift run) il n'y a pas de flux de mise à jour à interroger
            .disabled(!updater.isAvailable)

            // n'apparaît qu'une fois l'extension installée depuis le Marché
            if showPomodoro {
                Section(loc.s("Pomodoro", "Pomodoro")) { PomodoroSettingsFields() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PomodoroSettingsFields: View {
    @ObservedObject private var loc = Loc.shared
    @AppStorage(PomodoroSettings.Keys.work) private var work = 25.0
    @AppStorage(PomodoroSettings.Keys.shortBreak) private var shortBreak = 5.0
    @AppStorage(PomodoroSettings.Keys.longBreak) private var longBreak = 15.0
    @AppStorage(PomodoroSettings.Keys.sessions) private var sessions = 4

    var body: some View {
        Group {
            minutes(loc.s("Focus", "Concentration"), $work, 1...90)
            minutes(loc.s("Short break", "Pause courte"), $shortBreak, 1...30)
            minutes(loc.s("Long break", "Pause longue"), $longBreak, 1...60)
            Stepper(value: $sessions, in: 1...12) {
                LabeledContent(loc.s("Sessions before a long break",
                                     "Sessions avant une pause longue"), value: "\(sessions)")
            }
        }
        // un réglage ne prend effet qu'entre deux phases : on ne coupe pas un compte à rebours en cours
        .onChange(of: work) { _, _ in PomodoroModel.shared.settingsChanged() }
        .onChange(of: shortBreak) { _, _ in PomodoroModel.shared.settingsChanged() }
        .onChange(of: longBreak) { _, _ in PomodoroModel.shared.settingsChanged() }
        .onChange(of: sessions) { _, _ in PomodoroModel.shared.settingsChanged() }
    }

    private func minutes(_ title: String, _ value: Binding<Double>,
                         _ range: ClosedRange<Double>) -> some View {
        Stepper(value: value, in: range, step: 1) {
            LabeledContent(title, value: loc.s("\(Int(value.wrappedValue)) min",
                                               "\(Int(value.wrappedValue)) min"))
        }
    }
}

// ── Marché : catalogue distant d'extensions ───────────────────────
private struct MarketplaceView: View {
    @ObservedObject private var loc = Loc.shared
    @ObservedObject private var market = MarketModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "bag.fill").font(.title3).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(loc.s("Extensions", "Extensions")).font(.headline)
                        Text(loc.s("Add modules to your notch", "Ajoutez des modules à votre encoche"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                ForEach(market.extensions) { ext in
                    ExtensionRow(ext: ext)
                }
            }
            .padding(20)
        }
        .onAppear { market.refresh() }
    }
}

private struct ExtensionRow: View {
    let ext: Extension
    @ObservedObject private var loc = Loc.shared
    @ObservedObject private var market = MarketModel.shared

    private var installed: Bool { market.isInstalled(ext) }

    var body: some View {
        HStack(spacing: 12) {
            Text(ext.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.s(ext.nameEn, ext.nameFr)).font(.system(size: 13, weight: .semibold))
                Text(loc.s(ext.descEn, ext.descFr))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if market.canInstall(ext) {
                Button(installed ? loc.s("Remove", "Retirer") : loc.s("Get", "Obtenir")) {
                    market.toggle(ext)
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
                .tint(installed ? .secondary : .accentColor)
            } else {
                Text(loc.s("Coming soon", "Bientôt"))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.25)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(installed ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
    }
}

// ── Développer : proposer / contribuer une extension ──────────────
private struct DevelopView: View {
    @ObservedObject private var loc = Loc.shared

    private let repo = "https://github.com/ndaen/cubby-mac"
    private let newIssue = "https://github.com/ndaen/cubby-mac/issues/new"

    private let schema = """
    {
      "id": "my-extension",
      "emoji": "✨",
      "nameEn": "My Extension",  "nameFr": "Mon extension",
      "descEn": "What it does",  "descFr": "Ce qu'elle fait",
      "available": false
    }
    """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.s("Build an extension", "Créer une extension"))
                        .font(.title2.bold())
                    Text(loc.s(
                        "Cubby extensions are lightweight modules shown as tabs in the notch. The catalog is open source — propose an idea or contribute one on GitHub.",
                        "Les extensions Cubby sont des modules légers affichés en onglets dans l'encoche. Le catalogue est open source — propose une idée ou contribue sur GitHub."))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.s("Catalog entry format", "Format d'une entrée du catalogue"))
                        .font(.subheadline.weight(.semibold))
                    Text("catalog.json").font(.caption).foregroundStyle(.tertiary)
                    Text(schema)
                        .font(.system(.caption, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
                }

                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(URL(string: newIssue)!)
                    } label: {
                        Label(loc.s("Propose an extension", "Proposer une extension"),
                              systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSWorkspace.shared.open(URL(string: repo)!)
                    } label: {
                        Label(loc.s("View on GitHub", "Voir sur GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
