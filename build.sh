#!/bin/bash
# Baut Nodge.app (Universal: Apple-Chip + Intel). Optionen:
#   --run      danach starten
#   --install  nach /Applications kopieren und starten
#   --share    ~/Desktop/Nodge.zip zum Weitergeben erstellen (App + Anleitung)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Nodge.app"
TMP="build/tmp"
rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP"

# Direkt mit swiftc (SwiftPM braucht mit den reinen Command Line Tools teils Xcode).
# Einmal pro Architektur, danach mit lipo zu einem Binary zusammenführen.
SOURCES=$(find Sources/Nodge -name '*.swift')
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos13.0" -module-name Nodge $SOURCES -o "$TMP/Nodge-$ARCH"
done
lipo -create "$TMP/Nodge-arm64" "$TMP/Nodge-x86_64" -output "$APP/Contents/MacOS/Nodge"

cp Resources/Info.plist "$APP/Contents/Info.plist"
# Jetzt-läuft-Helfer (läuft im systemeigenen perl, siehe Helper/NowPlayingHelper.m)
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -framework Foundation -framework AppKit \
  Helper/NowPlayingHelper.m -o "$APP/Contents/Resources/NowPlayingHelper.dylib"
cp Helper/nowplaying.pl "$APP/Contents/Resources/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
rm -rf "$TMP"

xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Resources/NowPlayingHelper.dylib" 2>/dev/null || true
codesign --force --sign - "$APP" 2>/dev/null || echo "(Signatur übersprungen)"
echo "✓ $APP gebaut"

case "${1:-}" in
  --run)
    pkill -x Nodge 2>/dev/null || true; sleep 0.3
    open "$APP" ;;
  --install)
    pkill -x Nodge 2>/dev/null || true; sleep 0.3
    rm -rf /Applications/Nodge.app
    cp -R "$APP" /Applications/
    open /Applications/Nodge.app
    echo "✓ installiert in /Applications" ;;
  --share)
    SHARE="build/share/Nodge"
    rm -rf build/share
    mkdir -p "$SHARE"
    cp -R "$APP" "$SHARE/"
    cp Resources/Anleitung.txt "$SHARE/"
    ZIP="$HOME/Desktop/Nodge.zip"
    rm -f "$ZIP"
    # ditto erhält App-Struktur und Signatur (normales Zippen kann Bundles beschädigen)
    ditto -c -k --keepParent "$SHARE" "$ZIP"
    rm -rf build/share
    echo "✓ $ZIP erstellt – zum Weitergeben" ;;
esac
