#!/usr/bin/env bash
# Fensterübersicht (⌘Tab): alle Fenster aller Arbeitsflächen, „App · Titel“.
# Ersetzt „rofi -show window“, das unter Wayland nicht überall funktioniert.
source "$HOME/.config/sway/scripts/desktop-lib.sh"

# id<TAB>app_id/Klasse<TAB>Titel<TAB>Arbeitsfläche (Felder nie leer – read fasst
# leere Tab-Felder sonst zusammen)
mapfile -t wins < <(swaymsg -t get_tree -r | jq -r '
  def nonempty(d): if . == null or . == "" then d else gsub("[\t\n]"; " ") end;
  .. | objects | select(.type? == "workspace") | .name as $ws
  | recurse(.nodes[]?, .floating_nodes[]?)
  | select(.shell? != null)
  | [ (.id | tostring),
      (([.app_id, .window_properties.class?] | map(select(type == "string" and . != "")) | .[0])
        | nonempty("app")),
      (.name | nonempty("–")),
      (if $ws == "__i3_scratch" then "Ablage" else $ws end) ]
  | join("\t")')
(( ${#wins[@]} )) || exit 0

declare -A icon_of=()
rows=() ids=()
for w in "${wins[@]}"; do
  IFS=$'\t' read -r id app title ws <<<"$w"
  if [[ -z ${icon_of[$app]+x} ]]; then
    icon=${app,,}
    if path=$(desktop_path "$app.desktop" 2>/dev/null) || path=$(desktop_path "${app,,}.desktop" 2>/dev/null); then
      i=$(sed -n 's/^Icon=//p' "$path" | head -n1)
      [[ -n $i ]] && icon=$i
    fi
    icon_of[$app]=$icon
  fi
  name=${app##*.}; name=${name^}
  # Spalten App | Titel | Arbeitsfläche (menu.py richtet sie untereinander aus)
  rows+=("${name:-App}"$'\t'"$title"$'\t'"$ws"$'\0icon\x1f'"${icon_of[$app]}")
  ids+=("$id")
done

choice=$(printf '%s\n' "${rows[@]}" |
  python3 "$HOME/.config/sway/scripts/menu.py" -p "Fenster suchen" -w 720 -l 10)
[[ $choice =~ ^[0-9]+$ ]] || exit 0
id=${ids[$choice]}

# Fenster aus der Ablage holen, sonst einfach fokussieren
if swaymsg -t get_tree -r | jq -e --argjson id "$id" '
     [ .. | objects | select(.type? == "workspace" and .name == "__i3_scratch")
       | .. | objects | select(.id? == $id) ] | length > 0' >/dev/null; then
  swaymsg -q "[con_id=$id] scratchpad show"
else
  swaymsg -q "[con_id=$id] focus"
fi
