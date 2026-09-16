import SwiftUI

// Une extension = un module intégré présenté dans la marketplace.
// Le catalogue est distant (JSON), avec un repli embarqué si hors-ligne.
struct Extension: Identifiable, Decodable {
    let id: String
    let emoji: String
    let nameEn: String
    let nameFr: String
    let descEn: String
    let descFr: String
    let available: Bool
}

private struct Catalog: Decodable { let extensions: [Extension] }

@MainActor
final class MarketModel: ObservableObject {
    static let shared = MarketModel()

    @Published var extensions: [Extension] = MarketModel.bundled

    // Publier catalog.json à cette URL rend la liste modifiable sans mettre à jour l'app.
    private let url = URL(string: "https://raw.githubusercontent.com/ndaen/cubby/main/catalog.json")!

    func refresh() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let cat = try? JSONDecoder().decode(Catalog.self, from: data),
                  !cat.extensions.isEmpty
            else { return }               // hors-ligne / pas encore publié → on garde le repli
            extensions = cat.extensions
        }
    }

    // Extensions réellement câblées dans CE binaire → leur clé d'activation UserDefaults.
    // Seule source de vérité de ce qui est installable : le catalogue distant peut annoncer
    // d'autres id (available:false = "Bientôt"), mais il ne peut jamais activer une feature
    // que la version installée n'implémente pas. Livrer une extension = une ligne ici + son
    // case HubTab + sa vue. Aucune autre modif de MarketModel.
    private let wiredFlags: [String: String] = [
        "pomodoro": PomodoroSettings.Keys.installed,
    ]

    func canInstall(_ ext: Extension) -> Bool { ext.available && wiredFlags[ext.id] != nil }
    func isInstalled(_ ext: Extension) -> Bool {
        guard let key = wiredFlags[ext.id] else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }
    func toggle(_ ext: Extension) {
        guard let key = wiredFlags[ext.id] else { return }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        objectWillChange.send()
    }

    // ponytail: repli aligné sur le catalog.json distant à publier.
    static let bundled: [Extension] = [
        Extension(id: "weather", emoji: "🌦", nameEn: "Weather", nameFr: "Météo",
                  descEn: "Current weather at a glance",
                  descFr: "La météo en un coup d'œil", available: false),
        Extension(id: "pomodoro", emoji: "⏱", nameEn: "Pomodoro", nameFr: "Pomodoro",
                  descEn: "A focus timer that lives in the notch",
                  descFr: "Un minuteur de concentration dans l'encoche", available: true),
        Extension(id: "calendar", emoji: "📅", nameEn: "Agenda", nameFr: "Agenda",
                  descEn: "Your next event, always visible",
                  descFr: "Ton prochain événement, toujours visible", available: false),
    ]
}
