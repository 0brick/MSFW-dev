#!/usr/bin/env bash
# Sway neu laden, ohne dass Einstellungen verloren gehen (⌘⇧R, Installer).
# Sway setzt beim Neuladen Bildschirm-Anordnung, Skalierung und Auflösung
# zurück. Darum wird der Zustand vorher gesichert; services.sh (exec_always)
# stellt ihn nach dem Neuladen wieder her.
S="$HOME/.config/sway/scripts"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"

timeout 15 python3 "$S/displays.py" snapshot "$RUNTIME/outputs-before-reload.json" 2>/dev/null
swaymsg reload
