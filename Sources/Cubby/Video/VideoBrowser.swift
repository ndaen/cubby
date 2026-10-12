import Foundation
import AppKit

// Navigateur dont yt-dlp peut lire les cookies (`--cookies-from-browser`). Sert aux
// posts qui exigent une connexion (X « contenu sensible », Instagram, Facebook privé).
// `id` est exactement le nom attendu par yt-dlp.
enum VideoBrowser: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, brave, edge, vivaldi, opera, chromium, arc
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
        case .arc: "Arc"
        }
    }

    // Arc n'est pas connu de yt-dlp : ses cookies passent par `ChromiumCookies` (fichier temporaire).
    var ytdlpName: String? { self == .arc ? nil : rawValue }

    var appName: String {
        switch self {
        case .edge: "Microsoft Edge"
        case .chrome: "Google Chrome"
        case .brave: "Brave Browser"
        default: displayName
        }
    }

    // Identifiant de bundle → navigateur pris en charge par yt-dlp (nil sinon, ex. Arc).
    static func from(bundleID: String?) -> VideoBrowser? {
        switch bundleID {
        case "com.apple.Safari": .safari
        case "com.google.Chrome": .chrome
        case "org.mozilla.firefox": .firefox
        case "com.brave.Browser": .brave
        case "com.microsoft.edgemac": .edge
        case "com.vivaldi.Vivaldi": .vivaldi
        case "com.operasoftware.Opera": .opera
        case "org.chromium.Chromium": .chromium
        case "company.thebrowser.Browser": .arc
        default: nil
        }
    }

    // Navigateur par défaut du Mac : son nom d'affichage (même non pris en charge) et,
    // s'il l'est, l'équivalent yt-dlp.
    static func systemDefault() -> (name: String, browser: VideoBrowser?)? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
              let bundle = Bundle(url: url) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (name, from(bundleID: bundle.bundleIdentifier))
    }

    // Installés = présents dans /Applications ou ~/Applications.
    static func installed(fileManager fm: FileManager = .default) -> [VideoBrowser] {
        let dirs = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return allCases.filter { b in dirs.contains { fm.fileExists(atPath: "\($0)/\(b.appName).app") } }
    }

    // Arguments yt-dlp pour un identifiant enregistré ; nil / inconnu / « none » → aucun.
    // On revalide l'identifiant : une valeur UserDefaults périmée ne doit jamais devenir
    // un argument arbitraire passé au processus.
    // « default » = navigateur par défaut du Mac, résolu à l'appel (il peut changer) ; s'il
    // n'est pas pris en charge par yt-dlp, aucun cookie.
    static let defaultChoice = "default"

    static func resolve(_ id: String?, systemDefault: VideoBrowser? = VideoBrowser.systemDefault()?.browser) -> VideoBrowser? {
        id == defaultChoice ? systemDefault : id.flatMap(VideoBrowser.init(rawValue:))
    }

    // Arguments pour les navigateurs que yt-dlp lit lui-même (Arc : voir `resolve` + export).
    static func cookieArgs(for id: String?, systemDefault: VideoBrowser? = VideoBrowser.systemDefault()?.browser) -> [String] {
        guard let name = resolve(id, systemDefault: systemDefault)?.ytdlpName else { return [] }
        return ["--cookies-from-browser", name]
    }
}
