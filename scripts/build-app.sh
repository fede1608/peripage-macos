#!/bin/zsh
# Builds PeriPrint.app (release) into ./dist and the `peripage` CLI next to it.
#   scripts/build-app.sh            → dist/PeriPrint.app + dist/peripage
#   scripts/build-app.sh --install  → also copies the app to /Applications
set -euo pipefail
ROOT="${0:A:h:h}"
DIST="$ROOT/dist"
APP="$DIST/PeriPrint.app"

"$ROOT/scripts/swift.sh" build -c release --product PeriPrint
"$ROOT/scripts/swift.sh" build -c release --product peripage
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PeriPrint" "$APP/Contents/MacOS/PeriPrint"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${PERIPRINT_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PERIPRINT_VERSION" "$APP/Contents/Info.plist"
fi
cp "$BIN/peripage" "$DIST/peripage"

# Icon (drawn by scripts/make-icon.swift), cached in .build.
ICNS="$ROOT/.build/AppIcon.icns"
if [[ ! -f "$ICNS" || "$ROOT/scripts/make-icon.swift" -nt "$ICNS" ]]; then
  TMP="$(mktemp -d)"
  overlay=()
  [[ -f "$ROOT/.swiftpm-libs/overlay/vfs.yaml" ]] && overlay=(-vfsoverlay "$ROOT/.swiftpm-libs/overlay/vfs.yaml" -Xcc -ivfsoverlay -Xcc "$ROOT/.swiftpm-libs/overlay/vfs.yaml")
  swiftc -O "${overlay[@]}" "$ROOT/scripts/make-icon.swift" -o "$TMP/make-icon"
  "$TMP/make-icon" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ICNS"
  rm -rf "$TMP"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"
codesign --force --sign - --timestamp=none "$DIST/peripage"
echo "✓ $APP"
echo "✓ $DIST/peripage"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/PeriPrint.app
  cp -R "$APP" /Applications/
  echo "✓ Instalada en /Applications/PeriPrint.app"
fi
