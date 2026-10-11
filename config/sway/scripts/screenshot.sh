#!/usr/bin/env bash
# Bildschirmfotos & -aufnahmen: screenshot.sh gui|full|area|window|output
#   gui  = Auswahl wie macOS ⌘⇧5: Foto (Bereich, Fenster, Bildschirm, alle, Selbstauslöser,
#          bearbeiten) oder Video (Bildschirm/Bereich, ohne Ton, Systemton, Mikrofon)
# Fotos: ~/Bilder/Bildschirmfotos + Zwischenablage (grim + slurp).
# Videos: record.sh (wf-recorder), ~/Videos/Bildschirmaufnahmen.
pics=$(xdg-user-dir PICTURES 2>/dev/null)
[[ -z $pics || $pics == "$HOME" ]] && pics="$HOME/Pictures"   # ohne Bilder-Ordner meldet es $HOME
dir="$pics/Bildschirmfotos"
mkdir -p "$dir"
SLURP=(slurp -d -b 00000066 -c 0a84ffff -w 2)

# Dateiname mit dem Zeitpunkt der Aufnahme (nicht dem Öffnen des Menüs)
stamp() { file="$dir/Bildschirmfoto $(date '+%Y-%m-%d um %H.%M.%S').png"; }

focused_output() { swaymsg -t get_outputs -r | jq -r '.[] | select(.focused) | .name'; }

# Sichtbare Fenster als Auswahl-Rechtecke für slurp
window_boxes() {
  swaymsg -t get_tree -r | jq -r '.. | objects | select(.shell? != null and .visible? == true)
    | .rect | "\(.x),\(.y) \(.width)x\(.height)"'
}

shoot() { # shoot full|output|area|window|edit
  local g
  case $1 in
    full)   stamp; grim "$file" ;;
    output) stamp; grim -o "$(focused_output)" "$file" ;;
    area)   g=$("${SLURP[@]}") || exit 0; stamp; grim -g "$g" "$file" ;;
    window) g=$(window_boxes | "${SLURP[@]}" -r) || exit 0   # -r: nur Fenster wählbar
            stamp; grim -g "$g" "$file" ;;
    edit)   g=$("${SLURP[@]}") || exit 0
            stamp; grim -g "$g" - | swappy -f - -o "$file"
            [[ -s $file ]] || exit 0 ;;
  esac
  [[ -s $file ]] || exit 0   # abgebrochen
  wl-copy -t image/png < "$file"
  notify-send -a Bildschirmfoto -i "$file" "Bildschirmfoto gespeichert" "Auch in der Zwischenablage"
}

REC="$(dirname "$0")/record.sh"

# menu <platzhalter> <eintrag|icon|aktion …> → gewählte Aktion
# (Trennzeichen „|“ – Beschriftungen enthalten Doppelpunkte wie „Foto: …“ oder „0:12“)
menu() {
  local ph=$1 o l i choice; shift
  local -a opts=("$@")
  choice=$(for o in "${opts[@]}"; do IFS='|' read -r l i _ <<<"$o"; printf '%s\0icon\x1f%s\n' "$l" "$i"; done |
    python3 "$HOME/.config/sway/scripts/menu.py" -p "$ph" -w 440 -l 10)
  [[ $choice =~ ^[0-9]+$ ]] || return 1
  echo "${opts[$choice]##*|}"
}

case $1 in
  gui) # Bildschirmfoto & Aufnahme – wie macOS ⌘⇧5
    opts=()
    if [[ $("$REC" status) == *'"active":true'* ]]; then
      opts+=("Aufnahme beenden ($("$REC" status | jq -r .time))|media-playback-stop|rec-stop")
    fi
    opts+=("Foto: Bereich auswählen|selection-mode-symbolic|area"
           "Foto: Fenster|window-new|window"
           "Foto: dieser Bildschirm|video-display|output"
           "Foto: alle Bildschirme|computer|full"
           "Foto: Bildschirm in 5 Sekunden|alarm-symbolic|delay")
    command -v swappy >/dev/null && opts+=("Foto: Bereich auswählen und bearbeiten|document-edit|edit")
    if command -v wf-recorder >/dev/null; then
      opts+=("Video: Bildschirm aufnehmen …|media-record|rec-bildschirm"
             "Video: Bereich aufnehmen …|media-record|rec-bereich")
    fi
    action=$(menu "Bildschirmfoto & Aufnahme" "${opts[@]}") || exit 0
    case $action in
      rec-stop) exec "$REC" stop ;;
      rec-*)
        audio=$(menu "Ton für die Aufnahme" \
                  "Ohne Ton|audio-volume-muted-symbolic|ohne" \
                  "Mit Systemton (was du hörst)|audio-speakers-symbolic|system" \
                  "Mit Mikrofon|audio-input-microphone-symbolic|mikro") || exit 0
        sleep 0.5   # Menü samt Schließ-Animation (SwayFX) ausblenden lassen
        exec "$REC" start "${action#rec-}" "$audio" ;;
    esac
    sleep 0.5   # Menü samt Schließ-Animation (SwayFX) ausblenden lassen
    if [[ $action == delay ]]; then
      notify-send -a Bildschirmfoto -t 4000 "Bildschirmfoto in 5 Sekunden"
      sleep 5; shoot output
    else
      shoot "$action"
    fi ;;
  full)   shoot full ;;
  output) shoot output ;;
  window) shoot window ;;
  *)      shoot area ;;
esac
