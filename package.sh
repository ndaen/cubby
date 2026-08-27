#!/usr/bin/env bash
# Construit Cubby.app + Cubby-<version>.dmg + Cubby-<version>.zip dans ./dist.
# Source unique partagée par build-app.sh (install local) et la CI (release).
# Le DMG est l'artefact de première installation ; le ZIP est celui que Sparkle
# télécharge pour mettre à jour une app déjà installée.
# Usage : bash package.sh [version]   (défaut : 0.1.0)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-0.1.0}"
DIST="$DIR/dist"
APP="$DIST/Cubby.app"

# Clé publique EdDSA de l'appcast. Sa moitié privée vit dans le trousseau du
# mainteneur et dans le secret GitHub SPARKLE_PRIVATE_KEY — jamais dans le dépôt.
ED_PUBLIC_KEY="rnK7kylvGybc3oKNi2lO6K0HMmT8PZmb28aUQJcq/co="
FEED_URL="https://raw.githubusercontent.com/ndaen/cubby-mac/main/docs/appcast.xml"

echo "▸ build release…"
swift build -c release --package-path "$DIR"

echo "▸ assemblage du bundle (v$VERSION)…"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$DIR/.build/release/Cubby" "$APP/Contents/MacOS/Cubby"
if [ -f "$DIR/Logo/Cubby.icns" ]; then
  cp "$DIR/Logo/Cubby.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Sparkle : le chemin de l'artefact SPM change d'une version de toolchain à
# l'autre — on le retrouve, on ne le code pas en dur. `ditto` (et pas `cp -R`)
# préserve liens symboliques, permissions et signature du framework.
echo "▸ Sparkle…"
FW="$(find "$DIR/.build/artifacts" -type d -name 'Sparkle.framework' -path '*macos*' | head -1)"
[ -n "$FW" ] || { echo "✗ Sparkle.framework introuvable — lancer 'swift build' d'abord."; exit 1; }
ditto "$FW" "$APP/Contents/Frameworks/Sparkle.framework"
# le binaire est lié en @rpath : lui apprendre où chercher dans le bundle
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Cubby"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Cubby</string>
  <key>CFBundleDisplayName</key><string>Cubby</string>
  <key>CFBundleIdentifier</key><string>com.cubby.app</string>
  <key>CFBundleExecutable</key><string>Cubby</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Cubby controls Apple Music to show and control playback from the notch.</string>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$ED_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Signature ad-hoc (identifiant stable → TCC redemande proprement après rebuild).
# Surtout pas de --deep : il réécrirait la signature Developer ID que Sparkle
# livre déjà sur son framework et ses services XPC. On ne signe que notre app,
# le code imbriqué garde sa propre signature valide.
codesign --force --sign - --identifier com.cubby.app "$APP"

echo "▸ ZIP (canal de mise à jour)…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Cubby-$VERSION.zip"

echo "▸ DMG…"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Cubby.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Cubby" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Cubby-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "✅ dist/ :"
ls -1 "$DIST"
