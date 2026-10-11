#!/usr/bin/env bash
# Ausschalten-Menü (⌘⌃P)

entries=(
  "Sperren:system-lock-screen"
  "Ruhezustand:system-suspend"
  "Abmelden:system-log-out"
  "Neu starten:system-reboot"
  "Ausschalten:system-shutdown"
)

choice=$(
  for e in "${entries[@]}"; do printf '%s\0icon\x1f%s\n' "${e%%:*}" "${e#*:}"; done |
    python3 "$HOME/.config/sway/scripts/menu.py" -f s -p "Ausschalten, Neustart …" -w 340 -l 5
)

case $choice in
  Sperren)       "$HOME/.config/sway/scripts/lock.sh" ;;
  Ruhezustand)   systemctl suspend ;;
  Abmelden)      swaymsg exit ;;
  "Neu starten") systemctl reboot ;;
  Ausschalten)   systemctl poweroff ;;
esac
