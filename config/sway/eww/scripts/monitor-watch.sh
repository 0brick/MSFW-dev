#!/usr/bin/env bash
# Baut die Menüleisten neu auf, sobald Bildschirme an-/abgesteckt oder
# umgestellt werden (Anordnung, Skalierung, Auflösung).
source "$(dirname "$0")/lib.sh"

exec 8>"$RUNTIME/monitor-watch.lock"
flock -n 8 || exit 0

while true; do
  swaymsg -t subscribe -m -r '["output"]' 2>/dev/null | while read -r _; do
    # Eine Änderung löst oft mehrere Ereignisse aus – kurz sammeln
    while read -r -t 1.5 _; do :; done
    # 8>&- und eigenes stdin: weder die Sperre noch die Ereignis-Pipe darf an
    # launch-bars.sh (und einen dort gestarteten eww-Daemon) weitergereicht werden
    "$EWW_DIR/scripts/launch-bars.sh" 8>&- </dev/null
  done
  sleep 2 # Sway-IPC unterbrochen → erneut abonnieren
done
