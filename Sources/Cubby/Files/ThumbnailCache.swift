import AppKit
import QuickLookThumbnailing

// Vignettes de documents pour le bac : Quick Look d'abord (première page d'un
// PDF, l'image elle-même, l'aperçu Pages/Keynote…), icône système en repli.
// Les résultats sont gardés en mémoire : une vignette par (fichier, taille).
@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()

    private struct Key: Hashable {
        let path: String
        let side: CGFloat
    }

    @Published private var images: [Key: NSImage] = [:]

    // Vignette déjà connue, sans rien déclencher — pour un rendu immédiat.
    func cached(for url: URL, side: CGFloat) -> NSImage? {
        images[Key(path: url.path, side: side)]
    }

    // Vignette du fichier, générée une seule fois par taille demandée.
    func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        let key = Key(path: url.path, side: side)
        if let known = images[key] { return known }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = await Self.generate(url: url, side: side, scale: scale)
        images[key] = image
        return image
    }

    private static func generate(url: URL, side: CGFloat, scale: CGFloat) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .all
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            let cg = rep.cgImage
            return NSImage(cgImage: cg, size: CGSize(width: CGFloat(cg.width) / scale,
                                                     height: CGFloat(cg.height) / scale))
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
