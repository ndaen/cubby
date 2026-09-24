import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

@MainActor
final class FileShelf: ObservableObject {
    static let shared = FileShelf()
    @Published var items: [ShelfItem] = []

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(where: { $0.url == u }) {
            items.append(ShelfItem(url: u))
        }
    }
    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }
}

struct BacTabView: View {
    @StateObject private var shelf = FileShelf.shared
    @ObservedObject private var loc = Loc.shared
    @State private var targeted = false
    @State private var previewed: ShelfItem?
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if shelf.items.isEmpty {
                emptyZone
            } else {
                filledZone
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(targeted ? Color.cubby.opacity(0.12) : Color.clear)
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in shelf.add([url.standardizedFileURL]) }
                }
            }
            return true
        }
        .onChange(of: shelf.items) { _, items in
            // un fichier retiré ne doit pas laisser son aperçu derrière lui
            if let p = previewed, !items.contains(p) { hoverTask?.cancel(); previewed = nil }
        }
    }

    private var emptyZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(targeted ? Color.cubby : Color.secondary)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title)
                        .foregroundStyle(targeted ? AnyShapeStyle(Color.cubby) : AnyShapeStyle(.secondary))
                    Text(targeted ? loc.s("Drop here", "Déposez ici")
                                  : loc.s("Drag files here", "Glissez des fichiers ici")).font(.subheadline)
                    Text(loc.s("they stay within reach — drag them out anywhere you like",
                               "ils restent à portée — reglissez-les où vous voulez")).font(.caption2).foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            }
    }

    private var filledZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loc.s("\(shelf.items.count) file\(shelf.items.count > 1 ? "s" : "")",
                           "\(shelf.items.count) fichier\(shelf.items.count > 1 ? "s" : "")"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(loc.s("Clear", "Vider")) { shelf.clear() }.controlSize(.small).glassButton()
            }
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            FileChip(item: item,
                                     onRemove: { shelf.remove(item) },
                                     onHover: { hover(item, $0) })
                        }
                    }
                }
                .opacity(previewed == nil ? 1 : 0.28)

                // L'aperçu se pose PAR-DESSUS la rangée, sans capter la souris :
                // le survol du fichier reste actif, donc rien ne clignote. Il ne
                // sort jamais de la fenêtre — une popover ferait fuir le pointeur
                // hors de l'encoche, qui se refermerait toute seule.
                if let item = previewed {
                    FilePreviewCard(item: item)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                }
            }
        }
    }

    // Survol d'un fichier : l'aperçu apparaît après un court délai, disparaît aussitôt.
    private func hover(_ item: ShelfItem, _ inside: Bool) {
        hoverTask?.cancel()
        guard inside else {
            withAnimation(.easeOut(duration: 0.12)) { previewed = nil }
            return
        }
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { previewed = item }
        }
    }
}

struct FileChip: View {
    let item: ShelfItem
    let onRemove: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ThumbnailView(url: item.url, side: 44)
            Text(item.url.lastPathComponent)
                .font(.caption2).lineLimit(1).truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(8)
        .glassBG(RoundedRectangle(cornerRadius: 10), interactive: true)
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 10, height: 10)
            }
            .glassButton()
            .padding(2)
        }
        .help(item.url.lastPathComponent)
        .onHover(perform: onHover)
        // glisser le fichier VERS une autre app (Finder, Mail…)
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }
}

// Carte d'aperçu affichée au survol : grande vignette, nom complet, type et poids.
struct FilePreviewCard: View {
    let item: ShelfItem

    private var subtitle: String {
        let values = try? item.url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isDirectoryKey])
        let kind = values?.contentType?.localizedDescription ?? item.url.pathExtension.uppercased()
        guard values?.isDirectory != true, let size = values?.fileSize else { return kind }
        let weight = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return kind.isEmpty ? weight : "\(kind) — \(weight)"
    }

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(url: item.url, side: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 260, alignment: .leading)
        .glassBG(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// Vignette d'un fichier : aperçu Quick Look dès qu'il est prêt, icône système en attendant.
struct ThumbnailView: View {
    let url: URL
    let side: CGFloat

    @State private var thumb: NSImage?

    private var fallback: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    var body: some View {
        Image(nsImage: thumb ?? fallback)
            .resizable().scaledToFit()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            // un document clair a besoin d'un bord pour exister sur fond noir
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(thumb == nil ? 0 : 0.18), lineWidth: 0.5)
            }
            .task(id: url) {
                if let known = ThumbnailCache.shared.cached(for: url, side: side) {
                    thumb = known          // déjà connue : aucun clignotement
                } else {
                    thumb = await ThumbnailCache.shared.thumbnail(for: url, side: side)
                }
            }
    }
}
