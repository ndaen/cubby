# TODO — extension « Vidéo » (téléchargeur de liens → mp4)

Décisions validées : moteur **yt-dlp**, interface = **nouvel onglet « Vidéo »** (pas de drag & drop de lien sur l'encoche).

## Plan

- [x] **1. Logique pure + tests** — `Sources/Cubby/Video/VideoLink.swift`
  - `VideoLink.parse(_:)` : extrait la 1re URL http(s) d'un texte collé (les liens de partage contiennent souvent du texte autour), rejette le reste.
  - `YTDLPOutput` : parse les lignes `[download]  42.3% of ...` et le chemin final (`--print after_move:filepath`) → progression 0…1.
  - Tests dans `Tests/CubbyTests/VideoLinkTests.swift`.
- [x] **2. Moteur** — `Sources/Cubby/Video/VideoEngine.swift`
  - Binaire yt-dlp copié du bundle (`Resources/yt-dlp`) vers `~/Library/Application Support/Cubby/bin/` au 1er usage (le bundle est signé, on n'y écrit pas).
  - Mise à jour auto : `yt-dlp -U` sur la copie Application Support, au plus 1×/jour, en tâche de fond.
  - ffmpeg : cherché dans Application Support, puis `/opt/homebrew/bin`, `/usr/local/bin`. Absent → yt-dlp bascule sur un format mp4 déjà combiné (`b[ext=mp4]/b`) ; l'UI propose alors de télécharger ffmpeg (étape 4).
  - Options : `-f "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b" --merge-output-format mp4 --newline --no-playlist -o "~/Downloads/%(title).80B [%(id)s].%(ext)s"`.
  - `Process` async, annulable, stderr capturé pour des messages d'erreur lisibles.
- [x] **3. Modèle + onglet**
  - `VideoModel` (`@MainActor ObservableObject`) : états `idle / downloading(progress) / done(URL) / failed(message)`.
  - `Tabs/VideoTabView.swift` : champ lien (collage auto du presse-papiers à l'ouverture si c'est une URL), bouton Télécharger/Annuler, barre de progression, « Afficher dans le Finder » à la fin. Textes via `Loc` (FR/EN).
- [x] **4. Câblage** (comme le pomodoro)
  - `HubTab.video` + titres EN/FR dans `NotchShellModel.swift`.
  - `NotchRootView.swift` : flag `@AppStorage`, filtre des onglets, hauteur de l'onglet, `case .video`.
  - `MarketModel.swift` : `wiredFlags["video"]` + entrée dans `bundled`.
  - `catalog.json` : entrée `video`, `available: true`.
- [x] **5. Packaging** — `package.sh` télécharge `yt-dlp_macos` (version épinglée + SHA-256 vérifié) dans `Contents/Resources/`, `chmod +x`, signature ad-hoc incluse. Mettre à jour `THIRD-PARTY-NOTICES.md` (yt-dlp = Unlicense).
- [x] **6. Vérification** : `swift test`, `swift build`, puis téléchargement réel d'un lien public (X ou Instagram) et lecture du mp4 obtenu. Preuve : fichier présent dans `~/Downloads`, `ffprobe` OK.
- [ ] **7. Docs** : README + pages landing (FR/EN) — **après** la sortie, pas avant ; commit `docs:` séparé.

## Points d'attention

- **Release automatique** : un push sur `main` hors `docs/` publie une release + mise à jour Sparkle. Travailler sur une branche `feat/video-extension`, ne merger qu'une fois vérifié.
- **Modif non commitée existante** dans `NotchRootView.swift` (pas liée) : la committer ou la mettre de côté avant l'étape 4 pour garder des commits propres.
- **Fragilité** : les sites changent, yt-dlp se met à jour en quelques jours → d'où la mise à jour auto. Instagram/Facebook privés ou derrière login ne marcheront pas sans cookies (hors périmètre v1).
- **Usage** : pour du contenu dont l'utilisateur a le droit de garder une copie ; mention discrète dans l'UI.

## Review
- Tests : `swift test` → 18 verts (8 nouveaux sur le parsing lien/sortie yt-dlp).
- Vérifié pour de vrai : `VideoEngine` a téléchargé un mp4 H.264/AAC (ffprobe) avec progression ; un lien invalide remonte l'erreur yt-dlp lisible ; `package.sh` embarque yt-dlp (SHA-256 vérifié, `--version` OK).
- Bug trouvé en vérifiant : `--print` rend yt-dlp muet → ajout de `--no-quiet --progress`. AV1 non lisible partout → sélecteur de format H.264 d'abord.
- **Non vérifié** : l'onglet dans l'encoche (rendu, saisie clavier, copie depuis le bundle) et un lien Instagram/X/Facebook réel — à tester à la main sur `dist/Cubby.app`.
- Étape 7 (README + landing) volontairement non faite : après la release.
