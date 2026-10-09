#!/usr/bin/env bash
# PeriPrint installer for macOS (Apple silicon, macOS 14+).
#
#   curl -fsSL https://raw.githubusercontent.com/fede1608/peripage-macos/main/install.sh | bash
#
# Options (after `bash -s --`):
#   --no-driver        install only the app and the CLI, not the print driver
#   --version vX.Y.Z   install a specific release instead of the latest
#   --uninstall        remove the app, the CLI and the driver (keeps your presets and history)
#   --zip PATH         install from a local PeriPrint-macOS.zip (testing)
set -euo pipefail

REPO="fede1608/peripage-macos"
ASSET="PeriPrint-macOS.zip"
VERSION="latest"
WITH_DRIVER=1
UNINSTALL=0
LOCAL_ZIP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-driver) WITH_DRIVER=0 ;;
    --version) VERSION="${2:?falta la versión}"; shift ;;
    --uninstall) UNINSTALL=1 ;;
    --zip) LOCAL_ZIP="${2:?falta la ruta del zip}"; shift ;;
    -h|--help) echo "Opciones: --no-driver, --version vX.Y.Z, --uninstall, --zip RUTA"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "PeriPrint es solo para macOS."

app_dir() {
  if [[ -w /Applications ]]; then echo "/Applications"; else echo "$HOME/Applications"; fi
}

cli_dir() {
  if [[ -w /usr/local/bin ]]; then echo "/usr/local/bin"; else echo "$HOME/.local/bin"; fi
}

if [[ $UNINSTALL -eq 1 ]]; then
  say "Desinstalando PeriPrint…"
  pkill -f "PeriPrint.app/Contents/MacOS/PeriPrint" 2>/dev/null || true
  rm -rf "/Applications/PeriPrint.app" "$HOME/Applications/PeriPrint.app"
  rm -f "/usr/local/bin/peripage" "$HOME/.local/bin/peripage" 2>/dev/null || true
  lpadmin -x PeriPage_A6 2>/dev/null || true
  launchctl bootout "gui/$UID/app.periprint.driver" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/app.periprint.driver.plist"
  pkill -f "PeriPrint Driver.app/Contents/MacOS/PeriPrintDriver" 2>/dev/null || true
  rm -rf "$HOME/Applications/PeriPrint Driver.app"
  say "✓ Listo. Tus presets e historial quedan en ~/Library/Application Support/PeriPrint (borralo si querés)."
  exit 0
fi

[[ "$(uname -m)" == "arm64" ]] || fail "Por ahora los binarios son solo para Mac con Apple silicon (M1 o posterior)."
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "Hace falta macOS 14 Sonoma o posterior (tenés $(sw_vers -productVersion))."

if [[ "$VERSION" == "latest" ]]; then
  URL="https://github.com/$REPO/releases/latest/download/$ASSET"
else
  URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -n "$LOCAL_ZIP" ]]; then
  cp "$LOCAL_ZIP" "$TMP/$ASSET"
else
  say "Descargando PeriPrint ($VERSION)…"
  curl -fL --progress-bar -o "$TMP/$ASSET" "$URL" || fail "No pude descargar $URL"
fi
ditto -x -k "$TMP/$ASSET" "$TMP/pkg"

APPS="$(app_dir)"
mkdir -p "$APPS"
pkill -f "PeriPrint.app/Contents/MacOS/PeriPrint" 2>/dev/null || true
rm -rf "$APPS/PeriPrint.app"
ditto "$TMP/pkg/PeriPrint.app" "$APPS/PeriPrint.app"
xattr -dr com.apple.quarantine "$APPS/PeriPrint.app" 2>/dev/null || true
say "✓ PeriPrint.app → $APPS"

BIN="$(cli_dir)"
mkdir -p "$BIN"
install -m 755 "$TMP/pkg/peripage" "$BIN/peripage"
xattr -d com.apple.quarantine "$BIN/peripage" 2>/dev/null || true
say "✓ CLI peripage → $BIN/peripage"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "  (agregá $BIN a tu PATH para usar \`peripage\` desde la terminal)";; esac

if [[ $WITH_DRIVER -eq 1 ]]; then
  say "Instalando el driver de impresión…"
  bash "$TMP/pkg/driver/setup.sh" "$TMP/pkg/PeriPrint Driver.app"
fi

say "Listo. Abriendo PeriPrint (la primera vez macOS pide permiso de Bluetooth)."
open "$APPS/PeriPrint.app"
