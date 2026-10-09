#!/usr/bin/env bash
# Registers an already built "PeriPrint Driver.app":
#   ~/Applications/PeriPrint Driver.app, a login agent that keeps it running,
#   and the CUPS queue "PeriPage_A6" (driverless IPP Everywhere, served on localhost:8631).
# Usage: driver/setup.sh "/path/to/PeriPrint Driver.app"
set -euo pipefail

SOURCE="${1:?Uso: setup.sh \"/ruta/a/PeriPrint Driver.app\"}"
LABEL="app.periprint.driver"
DEST="$HOME/Applications/PeriPrint Driver.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
QUEUE="PeriPage_A6"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
pkill -f "PeriPrint Driver.app/Contents/MacOS/PeriPrintDriver" 2>/dev/null || true
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/PeriPrintDriver</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$UID" "$AGENT"
echo "✓ PeriPrint Driver instalado y en ejecución ($DEST)"

# Wait for the IPP server, then (re)create the CUPS queue.
for _ in $(seq 1 30); do
  curl -s -o /dev/null "http://localhost:8631/" && break
  sleep 0.5
done
lpadmin -p "$QUEUE" -D "PeriPage A6" -L "Bluetooth" -E -v "ipp://localhost:8631/ipp/print" -m everywhere
lpadmin -p "$QUEUE" -o printer-is-shared=false -o media=48x100mm.Borderless
echo "✓ Impresora “PeriPage A6” agregada: elegila con ⌘P en cualquier app."
