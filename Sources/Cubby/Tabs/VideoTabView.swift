import SwiftUI

struct VideoTabView: View {
    @ObservedObject var video: VideoModel
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField(loc.s("Paste a video link (Instagram, X, Facebook…)",
                                "Colle un lien de vidéo (Instagram, X, Facebook…)"),
                          text: $video.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glassBG(Capsule(), interactive: true)
                    .disabled(video.busy)
                    .onSubmit { video.start() }
                    // Seule une saisie de l'utilisateur efface le résultat précédent : le modèle vide
                    // lui-même le champ à la fin du téléchargement, ce qui ne doit pas masquer
                    // l'aperçu qu'il vient d'afficher.
                    .onChange(of: video.input) { _, new in if !new.isEmpty { video.reset() } }

                browserMenu

                if video.busy {
                    pill(loc.s("Cancel", "Annuler"), prominent: false) { video.cancel() }
                } else {
                    pill(loc.s("Download", "Télécharger"), prominent: true) { video.start() }
                        .disabled(video.link == nil)
                        .opacity(video.link == nil ? 0.45 : 1)
                }
            }
            status
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { video.prefillFromPasteboard() }
    }

    // Cookies d'un navigateur : pour les posts qui demandent une connexion.
    private var browserMenu: some View {
        let active = VideoBrowser.resolve(video.browser) != nil
        return Menu {
            Picker(loc.s("Use cookies from", "Utiliser les cookies de"), selection: $video.browser) {
                Text(loc.s("None", "Aucun")).tag("none")
                if let d = VideoBrowser.systemDefault(), d.browser != nil {
                    Text(loc.s("Default browser (\(d.name))", "Navigateur par défaut (\(d.name))"))
                        .tag(VideoBrowser.defaultChoice)
                }
                ForEach(VideoBrowser.installed()) { b in Text(b.displayName).tag(b.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: active ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.system(size: 14))
                .padding(7)
                .glassBG(Circle(), active: active, tint: .cubby.opacity(0.28), interactive: true)
                .foregroundStyle(active ? .primary : .secondary)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize()
        .disabled(video.busy)
        .help(loc.s("Use your browser's login for posts that need an account",
                    "Utilise la connexion de ton navigateur pour les posts qui demandent un compte"))
    }

    @ViewBuilder private var status: some View {
        switch video.state {
        case .idle:
            Text(loc.s("The mp4 is saved to your Downloads folder.",
                       "Le mp4 est enregistré dans ton dossier Téléchargements."))
                .font(.caption).foregroundStyle(.secondary)
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: max(p, 0.02)).tint(.cubby)
                    .animation(.linear(duration: 0.25), value: p)
                Text(loc.s("Downloading… \(Int(p * 100))%", "Téléchargement… \(Int(p * 100)) %"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .done(let file):
            HStack(spacing: 12) {
                Button { video.open(file) } label: { VideoThumb(file: file) }
                    .buttonStyle(.plain)
                    .help(loc.s("Open the video", "Ouvrir la vidéo"))
                VStack(alignment: .leading, spacing: 8) {
                    Label(file.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2).truncationMode(.middle)
                    HStack(spacing: 8) {
                        pill(loc.s("Open", "Ouvrir"), prominent: true) { video.open(file) }
                        pill(loc.s("Show in Finder", "Afficher dans le Finder"), prominent: false) { video.reveal(file) }
                    }
                }
                Spacer(minLength: 0)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red.opacity(0.9))
                .lineLimit(3)
        }
    }

    private func pill(_ title: String, prominent: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .glassBG(Capsule(), tint: prominent ? .cubby.opacity(0.28) : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// Aperçu de la vidéo téléchargée (image Quick Look, icône du fichier en repli).
private struct VideoThumb: View {
    let file: URL
    @State private var image: NSImage?
    private let width: CGFloat = 112, height: CGFloat = 66

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 3)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .task(id: file) {
            image = ThumbnailCache.shared.cached(for: file, side: 160)
            if image == nil { image = await ThumbnailCache.shared.thumbnail(for: file, side: 160) }
        }
    }
}
