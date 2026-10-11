#!/usr/bin/env bash
# Passendes Einstellungsfenster öffnen:
#   settings-app.sh network|bluetooth|sound|power|system
# Unter KDE (z. B. KDE neon) die einzelnen Module der Systemeinstellungen
# als eigenes Fenster, sonst GTK-Werkzeuge bzw. die GNOME-Einstellungen.
# Es werden nur Fenster geöffnet – kein Dienst, der in anderen Desktops mitläuft.

# KDE-Modul öffnen, falls installiert (kehrt sonst zurück)
kcm() { # Debian/Ubuntu: /usr/lib/<arch>/qt6, Arch: /usr/lib/qt6, Fedora/openSUSE: /usr/lib64/qt6
  local base found=0
  for base in /usr/lib/*/qt6 /usr/lib/qt6 /usr/lib64/qt6; do
    compgen -G "$base/plugins/plasma/kcms/*/$1.so" >/dev/null && { found=1; break; }
  done
  (( found )) || return 0
  if command -v kcmshell6 >/dev/null; then exec kcmshell6 "$1"; fi
  if command -v systemsettings >/dev/null; then exec systemsettings "$1"; fi
}

# GNOME-Einstellungen (verweigern sich außerhalb von GNOME ohne diese Variable)
gcc() { # gcc [bereich]
  command -v gnome-control-center >/dev/null &&
    XDG_CURRENT_DESKTOP=GNOME exec gnome-control-center "$@"
  return 0
}

# erstes vorhandene Programm starten
first() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null && exec "$c"; done
  notify-send -a Einstellungen "Keine Einstellungs-App gefunden" "Gesucht: $*"
}

case $1 in
  network)   kcm kcm_networkmanagement; first nm-connection-editor ;;
  bluetooth) kcm kcm_bluetooth;  gcc bluetooth; first blueman-manager ;;
  sound)     kcm kcm_pulseaudio;        first pavucontrol ;;
  power)     kcm kcm_energyinfo;        first gnome-power-statistics ;;
  system)    command -v systemsettings >/dev/null && exec systemsettings
             gcc; first lxappearance ;;
  *) echo "Aufruf: $0 network|bluetooth|sound|power|system" >&2; exit 1 ;;
esac
