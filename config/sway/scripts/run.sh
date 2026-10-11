#!/usr/bin/env bash
# Standard-Apps starten: run.sh browser [url]|files|calculator|clipboard|emoji
# KDE-Apps (Dolphin, KCalc) haben Vorrang, GTK-Apps sind der Ersatz.
first() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null && exec "$c"; done
}

# Zwischenablage-Verlauf: cliphist (Text und Bilder), sonst clipman
clipboard() {
  if command -v cliphist >/dev/null; then
    local sel
    sel=$(cliphist list | rofi -dmenu -i -p "" -display-columns 2 \
            -theme-str 'entry { placeholder: "Zwischenablage"; }') || exit 0
    [[ -n $sel ]] && cliphist decode <<<"$sel" | wl-copy
  elif command -v clipman >/dev/null; then
    exec clipman pick -t rofi -T'-p "" -theme-str "entry { placeholder: \"Zwischenablage\"; }"'
  else
    notify-send -a Zwischenablage "Kein Zwischenablage-Verlauf" "cliphist oder clipman installieren."
  fi
}

case $1 in
  browser)
    shift
    b=$(command -v firefox || command -v firefox-esr) && exec "$b" "$@"
    command -v flatpak >/dev/null && flatpak info org.mozilla.firefox >/dev/null 2>&1 &&
      exec flatpak run org.mozilla.firefox "$@"
    if [[ -n ${1:-} ]]; then exec xdg-open "$1"; else first x-www-browser; fi ;;
  files)      first dolphin nautilus ;;
  calculator) first kcalc gnome-calculator ;;
  clipboard)  clipboard ;;
  emoji)      exec rofimoji --action copy --skin-tone neutral ;;
esac
