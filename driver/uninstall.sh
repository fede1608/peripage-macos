#!/usr/bin/env bash
# Removes PeriPrint Driver, its login agent and the CUPS queue.
LABEL="app.periprint.driver"
lpadmin -x PeriPage_A6 2>/dev/null && echo "✓ Impresora PeriPage_A6 eliminada"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
pkill -f "PeriPrint Driver.app/Contents/MacOS/PeriPrintDriver" 2>/dev/null
rm -rf "$HOME/Applications/PeriPrint Driver.app"
echo "✓ PeriPrint Driver desinstalado"
