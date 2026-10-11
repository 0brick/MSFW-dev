#!/usr/bin/env bash
# Einstellungen (⌘⌃S) – zentrale Anlaufstelle für alle Konfigurationen
# Pfade für die Befehlszeile maskiert – funktioniert auch mit Leerzeichen im Benutzerordner
S=$(printf '%q' "$HOME/.config/sway/scripts")
C=$(printf '%q' "$HOME/.config")

# Bezeichnung:Symbol:Befehl (der Befehl läuft über bash -c und darf „:“ enthalten)
items=(
  "Bildschirme anordnen & skalieren:video-display:python3 $S/displays.py"
  "Autostart-Apps:system-run:$S/autostart-manager.sh"
  "Hintergrundbild:preferences-desktop-wallpaper:$S/wallpaper.sh select"
  "Erscheinungsbild (Hell/Dunkel):preferences-desktop-theme:$S/theme.sh menu"
  "Blaulichtfilter an/aus:night-light:$S/toggles.sh nightlight"
  "Tastenkürzel:preferences-desktop-keyboard-shortcuts:$S/keybindings.sh"
  "Favoriten im Launcher bearbeiten:starred:xdg-open $C/i3-apple/favorites"
  "Touchpad & Tastatur:input-touchpad:xdg-open $C/i3-apple/input"
  "WLAN & Netzwerk:preferences-system-network:$S/settings-app.sh network"
  "Bluetooth:bluetooth:$S/settings-app.sh bluetooth"
  "Ton:multimedia-volume-control:$S/settings-app.sh sound"
  "Energie & Akku:battery:$S/settings-app.sh power"
  "Systemeinstellungen:preferences-system:$S/settings-app.sh system"
  "Sway-Konfiguration bearbeiten:text-x-script:xdg-open $C/sway/config"
)

choice=$(for it in "${items[@]}"; do
           IFS=: read -r label icon _ <<<"$it"
           printf '%s\0icon\x1f%s\n' "$label" "$icon"
         done | python3 "$HOME/.config/sway/scripts/menu.py" -p "Einstellungen" -w 480 -l 14)

[[ $choice =~ ^[0-9]+$ ]] || exit 0
IFS=: read -r _ _ cmd <<<"${items[$choice]}"
setsid -f bash -c "$cmd" >/dev/null 2>&1 </dev/null
