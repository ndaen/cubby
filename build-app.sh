#!/usr/bin/env bash
# Construit et installe Cubby.app dans /Applications (usage dev local).
# La construction (app + DMG) est faite par package.sh, partagé avec la CI.
# Usage : bash build-app.sh [version]   (défaut : celui de package.sh)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$DIR/package.sh" "$@"

APP="/Applications/Cubby.app"
rm -rf "$APP"
cp -R "$DIR/dist/Cubby.app" "$APP"

# enlève la quarantaine (build local) et re-signe en ad-hoc pour éviter Gatekeeper
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - --identifier com.cubby.app "$APP" 2>/dev/null || true

echo "✅ $APP installé."
echo "   Lancer : open \"$APP\"   (ou double-clic dans /Applications)"
