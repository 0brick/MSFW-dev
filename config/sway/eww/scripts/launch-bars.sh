#!/usr/bin/env bash
# Startet den eww-Daemon und öffnet auf jedem aktiven Bildschirm eine Menüleiste.
source "$(dirname "$0")/lib.sh"

exec 9>"$RUNTIME/launch.lock"
flock 9

# eww.scss legt die Leiste auf dieses Symbol-Theme fest – fehlt es, findet GTK
# kein einziges Symbol. Normalerweise legt es der Installer an.
[[ -f ${XDG_DATA_HOME:-$HOME/.local/share}/icons/i3apple-sway-bar/index.theme ]] ||
  python3 "$EWW_DIR/scripts/bar-icons.py" >/dev/null 2>&1

if ! eww_ ping >/dev/null 2>&1; then
  eww_ daemon 9>&-
  for _ in $(seq 50); do
    eww_ ping >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

eww_ close-all >/dev/null 2>&1
: > "$RUNTIME/popup"
eww_ update popup=""   # auch bei ausgeblendeter Leiste – sonst liefen die Popup-Abfragen weiter
[[ -f $RUNTIME/bar-hidden ]] && exit 0   # mit Super+Strg+B ausgeblendet

# Sway-Ausgang → eww-Bildschirmnummer. eww zählt wie GTK; die Zuordnung
# läuft über die Position im Layout. Jede Nummer wird nur einmal vergeben –
# liegen zwei Bildschirme an derselben Stelle, bekäme sonst jeder dieselbe
# Nummer (doppelte bar_N). Übrige Ausgänge erhalten freie Nummern in Sways
# Reihenfolge.
mapfile -t outs < <(swaymsg -t get_outputs -r | jq -r '.[] | select(.active) | "\(.name)\t\(.rect.x)\t\(.rect.y)"')
mapfile -t gdk < <(python3 "$EWW_DIR/scripts/gdk-monitors.py" 2>/dev/null)
declare -A used=() idx_of=()
for o in "${outs[@]}"; do
  IFS=$'\t' read -r name x y <<<"$o"
  [[ -n $name ]] || continue
  for g in "${gdk[@]}"; do
    IFS=$'\t' read -r gi gx gy <<<"$g"
    [[ $gi =~ ^[0-9]+$ ]] || continue
    if [[ -z ${used[$gi]+x} && $gx == "$x" && $gy == "$y" ]]; then
      used[$gi]=1; idx_of[$name]=$gi; break
    fi
  done
done
n=${#gdk[@]}; (( n )) || n=${#outs[@]}   # ohne GTK-Liste: Sways Reihenfolge
for o in "${outs[@]}"; do
  name=${o%%$'\t'*}
  [[ -n $name && -z ${idx_of[$name]+x} ]] || continue
  for ((k = 0; k < n; k++)); do
    [[ -z ${used[$k]+x} ]] && { used[$k]=1; idx_of[$name]=$k; break; }
  done
done
for o in "${outs[@]}"; do
  name=${o%%$'\t'*}
  [[ -n $name && -n ${idx_of[$name]+x} ]] && printf '%s\t%s\n' "$name" "${idx_of[$name]}"
done > "$RUNTIME/monitors"

while IFS=$'\t' read -r out screen <&3; do
  eww_ open bar --id "bar_$screen" --screen "$screen" --arg "output=$out"
done 3< "$RUNTIME/monitors"

if [[ -f $SETTINGS/bat_show_pct ]]; then
  eww_ update bat_show_pct="$(cat "$SETTINGS/bat_show_pct")"
fi
