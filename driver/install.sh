#!/bin/zsh
# Builds PeriPrint Driver from source into dist/ and registers it (see driver/setup.sh).
#   driver/install.sh               → build + install
#   driver/install.sh --build-only  → only dist/PeriPrint Driver.app (used by CI)
# Uninstall with driver/uninstall.sh.
set -euo pipefail
ROOT="${0:A:h:h}"
STAGE="$ROOT/dist/PeriPrint Driver.app"

"$ROOT/scripts/swift.sh" build -c release --product PeriPrintDriver
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN/PeriPrintDriver" "$STAGE/Contents/MacOS/PeriPrintDriver"
cp "$ROOT/driver/Info.plist" "$STAGE/Contents/Info.plist"
cp "$ROOT/driver/peripage-a6.conf" "$STAGE/Contents/Resources/peripage-a6.conf"
if [[ -n "${PERIPRINT_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PERIPRINT_VERSION" "$STAGE/Contents/Info.plist"
fi
if [[ -f "$ROOT/.build/AppIcon.icns" ]]; then
  cp "$ROOT/.build/AppIcon.icns" "$STAGE/Contents/Resources/AppIcon.icns"
  sips -s format png -Z 128 "$ROOT/.build/AppIcon.icns" --out "$STAGE/Contents/Resources/printer-icon.png" >/dev/null
fi
codesign --force --sign - --timestamp=none "$STAGE"
echo "✓ $STAGE"

[[ "${1:-}" == "--build-only" ]] && exit 0
bash "$ROOT/driver/setup.sh" "$STAGE"
