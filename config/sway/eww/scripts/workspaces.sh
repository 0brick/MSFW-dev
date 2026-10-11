#!/usr/bin/env bash
# Liefert bei jeder Änderung die Sway-Arbeitsflächen als JSON.
#   workspaces.sh            fortlaufend (deflisten wsjson)
#   workspaces.sh goto <id>  zur Arbeitsfläche wechseln (Klick in der Leiste)

emit() {
  swaymsg -t get_workspaces -r 2>/dev/null |
    jq -c '[.[] | {id, num, name, focused, visible, urgent, output}]'
}

# Über die Knoten-ID statt über den Namen: Namen kommen so nie in die Befehlszeile
# der Leiste, und benannte Arbeitsflächen ohne Nummer (num = -1) funktionieren auch
if [[ ${1:-} == goto ]]; then
  [[ ${2:-} =~ ^[0-9]+$ ]] || exit 1
  cmd=$(swaymsg -t get_workspaces -r | jq -r --argjson id "$2" '
    first(.[] | select(.id == $id)
      | if .num >= 0 and (.name | test("^[0-9]+($|:)")) then "workspace number \(.num)"
        else "workspace " + (.name | @json) end) // empty')
  [[ -n $cmd ]] && exec swaymsg -q -- "$cmd"
  exit 1
fi

while true; do
  emit
  # -r: ein Ereignis pro Zeile
  swaymsg -t subscribe -m -r '["workspace","output"]' 2>/dev/null | while read -r _; do emit; done
  sleep 1
done
