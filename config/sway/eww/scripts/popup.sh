#!/usr/bin/env bash
# Öffnet/schließt die Popups der Menüleiste.
#   popup.sh <calendar|wifi|bluetooth|volume|battery|apps> <output>   – umschalten
#   popup.sh close                                                     – alle schließen
#   popup.sh launch <programm>                                         – schließen und App starten
source "$(dirname "$0")/lib.sh"

exec 9>"$RUNTIME/popup.lock"
flock 9

STATE="$RUNTIME/popup"
name=${1:-close}
output=${2:-}
current=$(cat "$STATE" 2>/dev/null || true)

close_all() {
  [[ -z $current ]] && return
  local screen
  eww_ close "${current%%@*}" >/dev/null 2>&1
  # eigener Deskriptor: eww darf die Liste nicht als stdin mitlesen
  while IFS=$'\t' read -r _ screen <&3; do
    eww_ close "closer_$screen" >/dev/null 2>&1
  done 3< "$RUNTIME/monitors"
  : > "$STATE"
  eww_ update popup=""
}

case $name in
  close)
    close_all; exit 0 ;;
  launch)
    close_all
    case $2 in # nur bekannte Programme starten
      network|bluetooth|sound|power)
                 cmd=("$HOME/.config/sway/scripts/settings-app.sh" "$2") ;;
      autostart) cmd=("$HOME/.config/sway/scripts/autostart-manager.sh") ;;
      *)         exit 1 ;;
    esac
    # 9>&-: die App darf die Sperre nicht erben – sonst hinge jeder weitere
    # Popup-Klick, bis ihr Fenster geschlossen ist
    command -v "${cmd[0]}" >/dev/null && setsid -f "${cmd[@]}" >/dev/null 2>&1 </dev/null 9>&-
    exit 0 ;;
  calendar|wifi|bluetooth|volume|battery|apps) ;;
  *) exit 1 ;;
esac

# Per Tastenkürzel ohne Output aufgerufen → Bildschirm mit Fokus
if [[ -z $output ]]; then
  output=$(swaymsg -t get_workspaces -r 2>/dev/null | jq -r '.[] | select(.focused) | .output')
fi

close_all
[[ "$name@$output" == "$current" ]] && exit 0   # zweiter Klick = schließen

screen=$(screen_of "$output")
screen=${screen:-0}

eww_ update popup="$name"
while IFS=$'\t' read -r _ s <&3; do
  eww_ open closer --id "closer_$s" --screen "$s" >/dev/null 2>&1 9>&-   # startet ggf. den Daemon
done 3< "$RUNTIME/monitors"
# Zustand schon vor dem Öffnen eintragen, damit close_all auch die Klickflächen
# eines halb geöffneten Popups wieder schließt
echo "$name@$output" > "$STATE"
if ! eww_ open "$name" --screen "$screen" 9>&-; then
  current="$name@$output"
  close_all
  exit 1
fi
