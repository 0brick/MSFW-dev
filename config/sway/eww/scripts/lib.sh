#!/usr/bin/env bash
# Gemeinsame Helfer für alle eww-Skripte (wird per `source` geladen).
# eww liegt in ~/.config/sway/eww – ~/.config/eww bleibt unberührt.

EWW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$HOME/.config/i3-apple"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
SESSION_LABEL=Sway
mkdir -p "$RUNTIME" "$SETTINGS"

EWW_BIN="$(command -v eww 2>/dev/null || echo "$HOME/.local/bin/eww")"

eww_() { "$EWW_BIN" -c "$EWW_DIR" "$@"; }

# Mitteilung, die eine vorherige mit gleichem Tag ersetzt
notify() { # notify <tag> <titel> [text]
  command -v notify-send >/dev/null || return 0
  notify-send -a "Systemeinstellungen" -h "string:x-dunst-stack-tag:$1" "$2" "${3:-}"
}

popup_open() { [[ "$(cat "$RUNTIME/popup" 2>/dev/null)" == "$1@"* ]]; }

# eww-Bildschirmnummer (GDK) zu einem Sway-Ausgang – steht in $RUNTIME/monitors
screen_of() { # screen_of <ausgang>
  awk -F'\t' -v o="$1" '$1 == o { print $2; exit }' "$RUNTIME/monitors" 2>/dev/null
}
