import Foundation

// Navigateur dont yt-dlp peut lire les cookies (`--cookies-from-browser`). Sert aux
// posts qui exigent une connexion (X « contenu sensible », Instagram, Facebook privé).
// `id` est exactement le nom attendu par yt-dlp.
enum VideoBrowser: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, brave, edge, vivaldi, opera, chromium
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .brave: "Brave"
        case .edge: "Edge"
        case .vivaldi: "Vivaldi"
        case .opera: "Opera"
        case .chromium: "Chromium"
        }
    }

    var appName: String {
        switch self {
        case .edge: "Microsoft Edge"
        case .chrome: "Google Chrome"
        case .brave: "Brave Browser"
        default: displayName
        }
    }

    // Installés = présents dans /Applications ou ~/Applications.
    static func installed(fileManager fm: FileManager = .default) -> [VideoBrowser] {
        let dirs = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return allCases.filter { b in dirs.contains { fm.fileExists(atPath: "\($0)/\(b.appName).app") } }
    }

    // Arguments yt-dlp pour un identifiant enregistré ; nil / inconnu / « none » → aucun.
    // On revalide l'identifiant : une valeur UserDefaults périmée ne doit jamais devenir
    // un argument arbitraire passé au processus.
    static func cookieArgs(for id: String?) -> [String] {
        guard let id, let b = VideoBrowser(rawValue: id) else { return [] }
        return ["--cookies-from-browser", b.rawValue]
    }
}
