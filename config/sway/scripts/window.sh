#!/usr/bin/env bash
# Fensteraktionen, die Sway nicht direkt kennt:
#   window.sh maximize    maximieren (Leiste bleibt sichtbar) / zurück (⌘M)
#   window.sh kill-app    alle Fenster der aktiven App schließen (⌘⇧Q)

# App-Kennung: app_id (Wayland) oder Fensterklasse (XWayland). Eine leere app_id
# zählt als fehlend – jqs „//“ greift nur bei null.
APP='([.app_id, .window_properties.class?] | map(select(type == "string" and . != "")) | .[0]) // ""'

focused() {
  swaymsg -t get_tree -r | jq -c "first(.. | objects | select(.focused? == true and .shell? != null))
    | {id, app: ($APP), floating: (.type == \"floating_con\"), rect, marks: (.marks // [])}"
}

case $1 in
  maximize)
    # Merkzeichen: _max_<id> (war gekachelt) oder _maxf_<id>_<x>_<y>_<b>_<h>
    # (war schwebend – Lage und Größe werden beim Zurückholen wiederhergestellt)
    f=$(focused); [[ -n $f ]] || exit 0
    id=$(jq -r .id <<<"$f")
    mark=$(jq -r --arg a "_max_$id" --arg b "_maxf_${id}_" \
      'first(.marks[] | select(. == $a or startswith($b))) // ""' <<<"$f")
    if [[ $mark == "_max_$id" ]]; then
      swaymsg -q "[con_id=$id] floating disable, unmark $mark"
    elif [[ -n $mark ]]; then
      IFS=_ read -r _ _ _ x y w h <<<"$mark"
      swaymsg -q "[con_id=$id] resize set $w px $h px, move absolute position $x px $y px, unmark $mark"
    elif [[ $(jq -r .floating <<<"$f") == true ]]; then
      geo=$(jq -r '.rect | "\(.x)_\(.y)_\(.width)_\(.height)"' <<<"$f")
      swaymsg -q "[con_id=$id] resize set 100 ppt 100 ppt, move position center, mark --add _maxf_${id}_$geo"
    else
      swaymsg -q "[con_id=$id] floating enable, resize set 100 ppt 100 ppt, move position center, mark --add _max_$id"
    fi ;;
  kill-app)
    f=$(focused); [[ -n $f ]] || exit 0
    app=$(jq -r .app <<<"$f")
    if [[ -z $app ]]; then
      swaymsg -q kill
    else
      swaymsg -t get_tree -r | jq -r --arg a "$app" ".. | objects
        | select(.shell? != null and ($APP) == \$a) | .id" |
        while read -r id; do swaymsg -q "[con_id=$id] kill"; done
    fi ;;
  *) echo "Aufruf: $0 maximize|kill-app" >&2; exit 1 ;;
esac
