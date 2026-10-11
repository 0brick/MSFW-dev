#!/usr/bin/env bash
# Einmalig beim Start der Sway-Sitzung: Umgebung weitergeben und Autostart-Apps.
# Die Dienste der Oberfläche (dunst, swayidle, Zwischenablage, kanshi …) startet
# services.sh – bei jedem Start und Neuladen, damit Abgestürztes wiederkommt.
# Eigene Autostart-Apps: Super+Strg+S → „Autostart-Apps“.
S="$HOME/.config/sway/scripts"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
exec >>"$RUNTIME/services.log" 2>&1
log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
log "── autostart.sh"

# Läuft gleichzeitig noch eine andere grafische Sitzung (z. B. Plasma oder GNOME
# auf einem anderen TTY)? Dann deren Umgebung bei systemd/D-Bus nicht überschreiben.
# Eigene Sitzung: XDG_SESSION_ID, sonst die Audit-Sitzung des Prozesses (logind
# vergibt dieselbe Nummer) – sonst zählte die eigene Sitzung als „andere“.
# Sitzungen, die gerade beendet werden (State=closing), zählen nicht.
other_gui_session() {
  local s type state own=${XDG_SESSION_ID:-$(cat /proc/self/sessionid 2>/dev/null)}
  for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3 == u { print $1 }'); do
    [[ $s == "$own" ]] && continue
    type=$(loginctl show-session "$s" -p Type --value 2>/dev/null)
    state=$(loginctl show-session "$s" -p State --value 2>/dev/null)
    [[ $state == closing ]] && continue
    [[ $type == x11 || $type == wayland ]] && return 0
  done
  return 1
}

# Wayland-Umgebung an D-Bus und systemd weitergeben (Portale für Bildschirm-
# freigabe und Dateidialoge, Flatpak-Apps, über D-Bus gestartete Programme).
# sway-apple-session entfernt sie beim Abmelden wieder.
vars=(WAYLAND_DISPLAY DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP)
if ! other_gui_session; then
  if timeout 10 dbus-update-activation-environment --systemd "${vars[@]}" ||
     timeout 10 systemctl --user import-environment "${vars[@]}"; then
    touch "$RUNTIME/env-exported"
    log "Umgebung an systemd/D-Bus weitergegeben"
  fi
else
  log "andere grafische Sitzung aktiv – Umgebung nicht weitergegeben"
fi

# Bildschirmprofil: lädt services.sh (läuft gleichzeitig, auch ohne kanshi)

# KDE: App-Datenbank aktualisieren (sonst ist „Öffnen mit“ in Dolphin leer)
command -v kbuildsycoca6 >/dev/null && setsid -f kbuildsycoca6 >/dev/null 2>&1 </dev/null

# XDG-Autostart (~/.config/autostart und /etc/xdg/autostart) – ohne die Apps,
# die in der Autostart-Verwaltung nur für Sway ausgeschaltet wurden
# (~/.config/i3-apple/autostart-disabled-sway). Einträge nur für andere
# Desktops (OnlyShowIn=KDE …) werden ausgelassen.
autostart_run() {
  local disabled="$HOME/.config/i3-apple/autostart-disabled-sway" f id tryexec
  declare -A path_of=()
  for f in /etc/xdg/autostart/*.desktop "$HOME/.config/autostart"/*.desktop; do
    [[ -f $f ]] && path_of[${f##*/}]=$f
  done
  for id in "${!path_of[@]}"; do
    f=${path_of[$id]}
    grep -qxF -- "$id" "$disabled" 2>/dev/null && continue
    grep -qE '^(Hidden=true|X-GNOME-Autostart-enabled=false)' "$f" && continue
    if grep -q '^OnlyShowIn=' "$f"; then grep -qE '^OnlyShowIn=(.*;)?sway(;|$)' "$f" || continue; fi
    grep -qE '^NotShowIn=(.*;)?sway(;|$)' "$f" && continue
    tryexec=$(sed -n 's/^TryExec=//p' "$f" | head -n1)
    [[ -n $tryexec ]] && ! command -v "$tryexec" >/dev/null && continue
    setsid -f dex "$f" >/dev/null 2>&1 </dev/null
    log "Autostart: $id"
  done
}
command -v dex >/dev/null && autostart_run
log "autostart.sh fertig"
