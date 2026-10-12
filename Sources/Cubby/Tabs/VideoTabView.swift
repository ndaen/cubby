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
                    .onChange(of: video.input) { _, _ in video.reset() }

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
        Menu {
            Picker(loc.s("Use cookies from", "Utiliser les cookies de"), selection: $video.browser) {
                Text(loc.s("None", "Aucun")).tag("none")
                ForEach(VideoBrowser.installed()) { b in Text(b.displayName).tag(b.id) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: video.browser == "none" ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 14))
                .padding(7)
                .glassBG(Circle(), active: video.browser != "none", tint: .cubby.opacity(0.28), interactive: true)
                .foregroundStyle(video.browser == "none" ? .secondary : .primary)
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
            HStack(spacing: 10) {
                Label(file.lastPathComponent, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                pill(loc.s("Show in Finder", "Afficher dans le Finder"), prominent: false) { video.reveal(file) }
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
