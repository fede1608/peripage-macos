#!/bin/zsh
# Packs the built apps into dist/PeriPrint-macOS.zip (the release asset install.sh downloads).
# Run after scripts/build-app.sh and driver/install.sh --build-only.
set -euo pipefail
ROOT="${0:A:h:h}"
DIST="$ROOT/dist"
PKG="$DIST/package"
rm -rf "$PKG" "$DIST/PeriPrint-macOS.zip"
mkdir -p "$PKG/driver"
ditto "$DIST/PeriPrint.app" "$PKG/PeriPrint.app"
ditto "$DIST/PeriPrint Driver.app" "$PKG/PeriPrint Driver.app"
cp "$DIST/peripage" "$PKG/peripage"
cp "$ROOT/driver/setup.sh" "$ROOT/driver/uninstall.sh" "$PKG/driver/"
(cd "$PKG" && ditto -c -k --norsrc --noextattr --noqtn . "$DIST/PeriPrint-macOS.zip")
rm -rf "$PKG"
echo "✓ $DIST/PeriPrint-macOS.zip ($(du -h "$DIST/PeriPrint-macOS.zip" | cut -f1))"
