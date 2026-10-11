#!/usr/bin/env bash
# Umschalter: toggles.sh nightlight|animations|gamemode|bar
#   animations = Effekte (Unschärfe, Schatten, Ecken, ab SwayFX 0.6 auch
#                Animationen) – nur mit SwayFX
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
EWW_DIR="$HOME/.config/sway/eww"
FX="$HOME/.config/sway/fx.conf"

flag() { [[ -f $RUNTIME/$1 ]]; }
set_flag() { if [[ $2 == on ]]; then touch "$RUNTIME/$1"; else rm -f "$RUNTIME/$1"; fi; }
note() { notify-send -a osd -u low -t 1500 -h "string:x-dunst-stack-tag:$1" "$2"; }
has_fx() { [[ -s $FX ]]; }

fx_off() {
  swaymsg -q 'blur disable; shadows disable; corner_radius 0; default_dim_inactive 0' 2>/dev/null
  # Animationen (SwayFX ab 0.6) nur, wenn fx.conf sie eingeschaltet hat –
  # ältere Versionen kennen den Befehl nicht
  if grep -q '^animation_duration_ms' "$FX" 2>/dev/null; then
    swaymsg -q 'animation_duration_ms 0' 2>/dev/null
  fi
}
fx_on() { # Befehle aus fx.conf erneut ausführen (layer_effects bleiben ohnehin bestehen –
          # per IPC würde Sway sie außerdem am „;“ zerteilen)
  local line
  while IFS= read -r line; do
    [[ -z $line || $line == \#* || $line == layer_effects* ]] && continue
    swaymsg -q -- "$line" 2>/dev/null
  done < "$FX"
}

case $1 in
  nightlight) # Blaulichtfilter (gammastep muss unter Wayland weiterlaufen)
    # Zustand am eigenen Prozess ablesen, nicht am Merkzeichen: ist gammastep
    # abgestürzt, schaltet der nächste Druck wieder ein statt nur „aus“ zu melden.
    # Beendet wird nur dieser eine gammastep, kein fremder.
    pidfile="$RUNTIME/gammastep.pid"
    pid=$(cat "$pidfile" 2>/dev/null)
    if [[ $pid =~ ^[0-9]+$ ]] && [[ $(ps -o comm= -p "$pid" 2>/dev/null) == gammastep ]]; then
      kill "$pid" 2>/dev/null
      rm -f "$pidfile"; set_flag nightlight off; note nightlight "Blaulichtfilter aus"
    elif command -v gammastep >/dev/null; then
      setsid -f bash -c 'echo $$ > "$1"; exec gammastep -m wayland -P -O 4000' _ "$pidfile" >/dev/null 2>&1
      set_flag nightlight on; note nightlight "Blaulichtfilter an"
    else
      note nightlight "Blaulichtfilter braucht gammastep"
    fi ;;
  animations)
    if ! has_fx; then
      note animations "Effekte gibt es nur mit SwayFX"
    elif flag no-effects; then
      set_flag no-effects off
      if flag gamemode; then   # Spielmodus hält die Effekte aus, bis er endet
        note animations "Effekte an – sobald der Spielmodus endet"
      else
        fx_on; note animations "Effekte an"
      fi
    else
      fx_off; set_flag no-effects on; note animations "Effekte aus"
    fi ;;
  gamemode) # Effekte & Mitteilungen aus für volle Leistung
    if flag gamemode; then
      has_fx && ! flag no-effects && fx_on
      dunstctl set-paused false
      set_flag gamemode off; note gamemode "Spielmodus aus"
    else
      note gamemode "Spielmodus an"; sleep 1
      has_fx && fx_off
      dunstctl set-paused true
      set_flag gamemode on
    fi ;;
  bar) # Menüleiste ein-/ausblenden
    if flag bar-hidden; then
      set_flag bar-hidden off; "$EWW_DIR/scripts/launch-bars.sh"
    else
      set_flag bar-hidden on
      # erst offene Popups schließen: leert $RUNTIME/popup und die eww-Variable
      # „popup“, sonst laufen deren Abfragen (WLAN-Suche …) unsichtbar weiter
      "$EWW_DIR/scripts/popup.sh" close
      "$HOME/.local/bin/eww" -c "$EWW_DIR" close-all 2>/dev/null ||
        eww -c "$EWW_DIR" close-all
    fi ;;
  effects-off) # für services.sh: nach dem Neuladen ausgeschaltet lassen
    has_fx && fx_off ;;
  *) echo "Aufruf: $0 nightlight|animations|gamemode|bar" >&2; exit 1 ;;
esac
