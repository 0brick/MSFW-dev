#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Bildschirme anordnen (⌘P)
#  Schnellauswahl wie Win+P, visueller Editor mit Skalierung (displays.py)
#  und gespeicherte Profile (kanshi – werden beim Anstecken automatisch geladen).
# ═══════════════════════════════════════════════════════════════════
SCRIPTS="$HOME/.config/sway/scripts"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
# Über python3 aufrufen – funktioniert auch, wenn das Ausführungsrecht fehlt
D() { python3 "$SCRIPTS/displays.py" "$@"; }

# Nach Namen sortiert – dieselbe Regel wie split_internal() in displays.py, damit
# „Nur …“ genau den Bildschirm nennt, den „quick internal“ auch nimmt
mapfile -t outputs < <(swaymsg -t get_outputs -r | jq -r '[.[].name] | sort | .[]')
internal=""
external=()
for o in "${outputs[@]}"; do
  if [[ -z $internal && $o =~ ^(eDP|LVDS|DSI) ]]; then internal=$o; else external+=("$o"); fi
done
# Ohne Laptop-Panel gilt der erste Bildschirm (nach Namen) als „Hauptbildschirm“
if [[ -z $internal && ${#external[@]} -gt 0 ]]; then internal=${external[0]}; external=("${external[@]:1}"); fi

save_profile() {
  local name
  name=$(rofi -dmenu -p "" -l 0 -mesg "Name für die aktuelle Anordnung (z. B. Büro, Zuhause)" \
         -theme-str 'entry { placeholder: "Profilname"; } listview { enabled: false; }' </dev/null)
  name=${name//[$'\t\r\n']/}
  [[ -n $name ]] || return
  D save "$name"
}

# Fenster losgelöst starten; Fehler landen im Protokoll und als Mitteilung
open_editor() {
  setsid -f python3 "$SCRIPTS/displays.py" >"$RUNTIME/displays.out" 2>&1 </dev/null
}

# Menüeinträge: Text + Aktion (Auswahl per Index, nicht per Textvergleich)
labels=() icons=() actions=()
add() { labels+=("$1"); icons+=("$2"); actions+=("$3"); }

if (( ${#external[@]} )); then
  add "Erweitern – extern rechts"      video-display                  "quick extend-right"
  add "Erweitern – extern links"       video-display                  "quick extend-left"
  add "Erweitern – extern oben"        video-display                  "quick extend-above"
  add "Spiegeln"                       video-joined-displays-symbolic "quick mirror"
  add "Nur $internal"                  computer                       "quick internal"
  add "Nur extern (${external[*]})"    video-display                  "quick external"
fi
add "Anordnung & Skalierung bearbeiten …"       preferences-desktop-display "editor"
add "Aktuelle Anordnung als Profil speichern …" document-save               "save"
while IFS= read -r p; do
  [[ -n $p ]] && add "Profil laden: $p" folder-saved-search "load:$p"
done < <(D profiles 2>/dev/null)

choice=$(for i in "${!labels[@]}"; do printf '%s\0icon\x1f%s\n' "${labels[$i]}" "${icons[$i]}"; done |
  python3 "$SCRIPTS/menu.py" -p "Bildschirme anordnen" -m "Bildschirme: ${outputs[*]}" -w 460 -l 10)
[[ $choice =~ ^[0-9]+$ ]] || exit 0

case ${actions[$choice]} in
  editor)  open_editor ;;
  save)    save_profile ;;
  quick\ *) D quick "${actions[$choice]#quick }" ;;
  load:*)  D load "${actions[$choice]#load:}" ;;
esac
# Menüleisten und Hintergrund passen sich selbst an (monitor-watch.sh, swaybg)
