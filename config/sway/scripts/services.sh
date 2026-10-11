#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Dienste der Sway-Sitzung sicherstellen – startet nur, was fehlt.
#  Läuft beim Start und bei jedem Neuladen (Super+Shift+R), daher reicht
#  ein Neuladen, wenn ein Dienst abgestürzt ist.
#  Protokoll: $XDG_RUNTIME_DIR/sway-apple/services.log
# ═══════════════════════════════════════════════════════════════════
S="$HOME/.config/sway/scripts"
S_EWW="$HOME/.config/sway/eww/scripts"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
LOG="$RUNTIME/services.log"

# Protokoll klein halten – in derselben Datei kürzen statt sie zu ersetzen:
# autostart.sh schreibt gleichzeitig hinein, seine Zeilen landeten sonst in
# der alten, gelöschten Datei
if [[ -f $LOG ]] && (( $(wc -l < "$LOG") > 400 )); then
  tail -n 200 "$LOG" > "$LOG.tmp" && cat "$LOG.tmp" > "$LOG"; rm -f "$LOG.tmp"
fi
exec >>"$LOG" 2>&1
log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
log "── services.sh (Sway ${SWAYSOCK:+läuft}, DISPLAY=${DISPLAY:-–})"

# Nie zweimal gleichzeitig (Start und Neuladen können sich überschneiden)
exec 9>"$RUNTIME/services.lock"
flock -w 30 9 || { log "anderer Lauf blockiert – abgebrochen"; exit 0; }

have()    { command -v "$1" >/dev/null 2>&1; }
running() { pgrep -u "$USER" -f "$1" >/dev/null 2>&1; }
# start <name> <befehl …> – losgelöst, ohne Protokoll- und Sperr-Dateideskriptoren
start() {
  local name=$1; shift
  setsid -f "$@" >/dev/null 2>&1 </dev/null 9>&-
  log "gestartet: $name"
}

# Bildschirme: Sway setzt sie beim Neuladen zurück → den vor dem Neuladen
# gesicherten Zustand (reload.sh) wiederherstellen, sonst das gespeicherte
# Profil dieser Bildschirm-Kombination. Angewendet wird nur, was abweicht.
if [[ -f $RUNTIME/outputs-before-reload.json ]]; then
  timeout 20 python3 "$S/displays.py" apply-snapshot "$RUNTIME/outputs-before-reload.json" 9>&- &&
    log "Bildschirme: Zustand vor dem Neuladen wiederhergestellt"
else
  timeout 20 python3 "$S/displays.py" restore 9>&- && log "Bildschirme: gespeichertes Profil geprüft"
fi

# Bildschirmprofile: kanshi lädt beim Anstecken das passende Profil
if have kanshi; then
  pgrep -u "$USER" -x kanshi >/dev/null || start kanshi kanshi
fi

# Effekte, die mit Super+Shift+A oder dem Spielmodus abgeschaltet wurden,
# bleiben aus – das Neuladen liest fx.conf sonst wieder ein
if [[ -s $HOME/.config/sway/fx.conf ]] && [[ -f $RUNTIME/no-effects || -f $RUNTIME/gamemode ]]; then
  "$S/toggles.sh" effects-off && log "Effekte bleiben ausgeschaltet"
fi

# GTK-Einstellungen für X-Programme (XWayland) – eigene Datei, nur dieser xsettingsd
XS="$HOME/.config/i3-apple/xsettingsd.conf"
if have xsettingsd && [[ -n ${DISPLAY:-} && -f $XS ]]; then
  running "xsettingsd -c $XS" || start xsettingsd xsettingsd -c "$XS"
fi

# Theme und Symbole passend zu Hell/Dunkel in die eigene dconf-Datenbank – einmal
# pro Sitzung (nicht bei jedem Neuladen), mit Zeitgrenze, damit ein hängendes
# gsettings den Rest nicht blockiert. Eigene Änderungen an Schrift/Cursor bleiben.
mark="$RUNTIME/theme-applied-${SWAYSOCK##*/}"   # Sway-Socket enthält die PID → je Sitzung
if [[ ! -f $mark ]]; then
  if timeout 15 "$S/theme.sh" apply 9>&-; then
    touch "$mark"
    log "theme.sh apply: ok"
  else
    log "theme.sh apply: Fehler oder Zeitüberschreitung (Code $?)"
  fi
fi

# Symbol-Theme der Menüleiste einmal pro Sitzung abgleichen (z. B. nachdem
# WhiteSur aktualisiert wurde) – ändert nur, was abweicht
mark="$RUNTIME/bar-icons-${SWAYSOCK##*/}"
if [[ ! -f $mark ]]; then
  out=$(timeout 20 python3 "$S_EWW/bar-icons.py" 2>&1 9>&-)
  touch "$mark"
  log "bar-icons.py: ${out:-keine Ausgabe}"
fi

# Mitteilungen: dunst mit der Sway-eigenen Konfiguration
pgrep -u "$USER" -x dunst >/dev/null ||
  start dunst dunst -config "$HOME/.config/sway/dunst/dunstrc"

# Passwortabfragen für Systemaktionen (polkit) – KDE-Agent bevorzugt
if ! running 'polkit-(kde|gnome)-authentication-agent-1'; then
  for agent in /usr/lib/*/libexec/polkit-kde-authentication-agent-1 \
               /usr/libexec/polkit-kde-authentication-agent-1 \
               /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
               /usr/libexec/polkit-gnome-authentication-agent-1 \
               /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1; do
    if [[ -x $agent ]]; then start polkit "$agent"; break; fi
  done
fi

# KDE: ältere Tray-Symbole (XEmbed, über XWayland) in der Menüleiste anzeigen –
# nur auf Wunsch (Datei ~/.config/i3-apple/xembed-tray anlegen). xembedsniproxy
# legt je Symbol ein schwarzes X11-Fenster bei 0,0 an und macht es nur per
# Deckkraft-Hinweis unsichtbar; den beachtet allein KWin. In Sway liegt es als
# schwarzes Quadrat über der linken Ecke der Menüleiste.
if [[ -f $HOME/.config/i3-apple/xembed-tray ]]; then
  if [[ -n ${DISPLAY:-} ]] && have xembedsniproxy && ! pgrep -u "$USER" -x xembedsniproxy >/dev/null; then
    start xembedsniproxy sh -c 'sleep 3; exec xembedsniproxy'
  fi
else
  # Einen früher von dieser Sitzung gestarteten beenden – nur den mit unserem
  # Sway-Socket, ein xembedsniproxy einer Plasma-Sitzung bleibt unberührt
  for pid in $(pgrep -u "$USER" -x xembedsniproxy); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qxF "SWAYSOCK=${SWAYSOCK:-}"; then
      kill "$pid" 2>/dev/null && log "xembedsniproxy beendet (nicht eingeschaltet)"
    fi
  done
fi

# Zwischenablage-Verlauf (Super+V)
if have cliphist && have wl-paste; then
  running 'wl-paste --type text --watch cliphist'  || start "cliphist (Text)"  wl-paste --type text --watch cliphist store
  running 'wl-paste --type image --watch cliphist' || start "cliphist (Bilder)" wl-paste --type image --watch cliphist store
elif have clipman && have wl-paste; then
  running 'wl-paste.*clipman' || start clipman wl-paste -t text --watch clipman store --no-persist
fi

# Bildschirmsperre nach 10 Minuten, Bildschirme eine Minute später aus,
# immer vor dem Ruhezustand; „loginctl lock-session“ sperrt ebenfalls
if have swayidle; then
  minor=$(swaymsg -t get_version -r 2>/dev/null | jq -r '.minor // 0' 2>/dev/null)
  if (( ${minor:-0} >= 8 )); then off='output * power off' on='output * power on'
  else off='output * dpms off' on='output * dpms on'; fi
  pgrep -u "$USER" -x swayidle >/dev/null || start swayidle swayidle -w \
    timeout 600 "$S/lock.sh" \
    timeout 660 "swaymsg '$off'" resume "swaymsg '$on'" \
    before-sleep "$S/lock.sh" \
    lock "$S/lock.sh"
fi

# Menüleisten neu aufbauen, wenn Bildschirme sich ändern
running "$S_EWW/monitor-watch.sh" || running 'eww/scripts/monitor-watch.sh' ||
  start monitor-watch "$S_EWW/monitor-watch.sh"

# Nach ein paar Sekunden prüfen, ob alles noch läuft (sofort abstürzende Dienste)
sleep 3
for p in kanshi dunst swayidle; do
  have "$p" && ! pgrep -u "$USER" -x "$p" >/dev/null && log "WARNUNG: $p läuft nicht (sofort beendet?)"
done
running 'eww/scripts/monitor-watch.sh' || log "WARNUNG: monitor-watch.sh läuft nicht"
log "fertig"
