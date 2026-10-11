#!/usr/bin/env bash
# Sperrbildschirm: weichgezeichneter Screenshot je Bildschirm wie bei macOS.
# Kehrt zurück, sobald gesperrt ist (swayidle wartet darauf vor dem Ruhezustand).
# Mit eingerichtetem Fingerabdruck (fprintd, wie am GDM-Anmeldebildschirm)
# entsperrt auch der Finger – fingerprint.sh läuft dafür neben swaylock.
pgrep -x swaylock >/dev/null && exit 0

S="$HOME/.config/sway/scripts"
dir="${XDG_RUNTIME_DIR:-/tmp}/sway-apple/lock"
mkdir -p "$dir"
rm -f "$dir"/*.png
im=$(command -v magick || command -v convert)

# Fingerabdruck nutzbar? (Leser, eingerichteter Finger, swaylock ≥ 1.6) –
# Ergebnis 30 Minuten gemerkt und mit Zeitgrenze: Vor dem Ruhezustand wartet
# logind nur wenige Sekunden auf die Sperre
cache="${dir%/lock}/fingerprint.available"
if [[ -f $cache && -n $(find "$cache" -mmin -30 2>/dev/null) ]]; then
  finger=$(<"$cache")
else
  finger=0
  timeout 2 "$S/fingerprint.sh" available 2>/dev/null && finger=1
  echo "$finger" > "$cache"
fi
[[ $finger == 1 ]] || finger=0

# Hinweis unten auf dem Sperrbild; Schrift wie in der Menüleiste, sonst die
# Standardschrift von fontconfig
font=$(fc-match -f '%{file}' 'SF Pro Text:semibold' 2>/dev/null)

args=()
if command -v grim >/dev/null && [[ -n $im ]]; then
  while read -r out height; do
    img="$dir/$out.png"
    grim -o "$out" "$img" 2>/dev/null || continue
    hint=()
    if (( finger )); then
      size=$(( ${height:-1080} / 48 )); (( size < 14 )) && size=14
      hint=(-gravity south -fill 'rgba(255,255,255,0.85)' ${font:+-font "$font"}
            -pointsize "$size" -annotate "+0+$(( ${height:-1080} / 9 ))"
            "Finger auflegen oder Passwort eingeben")
    fi
    "$im" "$img" -scale 10% -blur 0x2 -resize 1000% -fill black -colorize 25% "${hint[@]}" "$img" &&
      args+=(-i "$out:$img")
  done < <(swaymsg -t get_outputs -r | jq -r '.[] | select(.active) | "\(.name) \(.current_mode.height // 1080)"')
fi
# Farbe immer mitgeben: gilt für jeden Bildschirm ohne eigenes Bild – auch
# einen, der erst während der Sperre angesteckt wird (sonst swaylocks Grau)
args+=(-c 1e1e20)

paused=$(dunstctl is-paused 2>/dev/null)
dunstctl set-paused true 2>/dev/null

# -f: erst zurückkehren, wenn gesperrt ist; -e: leere Eingabe ignorieren; -F: Fehlversuche zeigen
swaylock -f -e -F "${args[@]}"
rm -f "$dir"/*.png

# Fingerabdruck parallel zum Passwort – endet von selbst, sobald entsperrt ist
if (( finger )); then
  setsid -f "$S/fingerprint.sh" >/dev/null 2>&1 </dev/null
fi

# Mitteilungen erst nach dem Entsperren wieder zulassen
if [[ $paused == false ]]; then
  setsid -f bash -c 'while pgrep -x swaylock >/dev/null; do sleep 1; done; dunstctl set-paused false' \
    >/dev/null 2>&1 </dev/null
fi
