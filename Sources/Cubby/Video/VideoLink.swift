import Foundation

// Logique pure de l'extension Vidéo : extraire un lien d'un texte collé et lire
// la sortie de yt-dlp. Aucune E/S ici, donc testable sans réseau ni processus.
enum VideoLink {
    // Les liens de partage arrivent souvent entourés de texte (« Regarde ça : https://… »).
    // On prend la première URL http(s) avec un hôte.
    static func parse(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        for m in detector?.matches(in: text, range: range) ?? [] {
            guard let url = m.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host != nil
            else { continue }
            return url
        }
        return nil
    }
}

// Une ligne de la sortie standard de yt-dlp (lancé avec --newline).
enum YTDLPLine: Equatable {
    case progress(Double)      // 0…1
    case finished(String)      // chemin du fichier final
    case other

    static let finishedPrefix = "CUBBY_DONE:"

    static func parse(_ raw: String) -> YTDLPLine {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix(finishedPrefix) {
            return .finished(String(line.dropFirst(finishedPrefix.count)))
        }
        // « [download]  42.3% of ~ 10.00MiB at … »
        if line.hasPrefix("[download]"), let pct = line.firstIndex(of: "%") {
            let head = line[..<pct].split(separator: " ").last ?? ""
            if let v = Double(head) { return .progress(min(max(v / 100, 0), 1)) }
        }
        return .other
    }

    // Dernière ligne « ERROR: … » de stderr, lisible par un humain.
    static func errorMessage(from stderr: String) -> String? {
        stderr.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix("ERROR:") }
            .map { $0.dropFirst("ERROR:".count).trimmingCharacters(in: .whitespaces) }
    }
}
