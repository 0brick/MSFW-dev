#!/usr/bin/env bash
# Laufende Fenster für das Popup „Hintergrund-Apps“.
#   apps.sh list | focus <con_id> | close <con_id>
source "$(dirname "$0")/lib.sh"

list() {
  swaymsg -t get_tree -r 2>/dev/null | jq -c '
    [ .. | objects | select(.type? == "workspace") | .name as $ws
      | recurse(.nodes[]?, .floating_nodes[]?)
      | select(.shell? != null)
      | {
          id,
          ws: (if $ws == "__i3_scratch" then "Ablage" else $ws end),
          app: ((([.app_id, .window_properties.class?] | map(select(type == "string" and . != "")) | .[0]) // "")
                | split(".") | (last // "")
                | if . == "" then "App" else (.[0:1] | ascii_upcase) + .[1:] end),
          title: (.name // "")
        }
    ] | .[:14]'
}

in_scratchpad() {
  swaymsg -t get_tree -r | jq -e --argjson id "$1" '
    [ .. | objects | select(.type? == "workspace" and .name == "__i3_scratch")
      | .. | objects | select(.id? == $id) ] | length > 0' >/dev/null
}

case $1 in
  list) list ;;
  focus)
    [[ $2 =~ ^[0-9]+$ ]] || exit 1
    "$EWW_DIR/scripts/popup.sh" close
    if in_scratchpad "$2"; then
      swaymsg -q "[con_id=$2] scratchpad show"
    else
      swaymsg -q "[con_id=$2] focus"
    fi
    ;;
  close)
    [[ $2 =~ ^[0-9]+$ ]] || exit 1
    swaymsg -q "[con_id=$2] kill"
    sleep 0.3
    eww_ update apps_list="$(list)"
    ;;
  *) echo "Aufruf: $0 list|focus <id>|close <id>" >&2; exit 1 ;;
esac
