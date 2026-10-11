#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Hintergrundbild (Sway, swaybg)
#    wallpaper.sh            aktuelles Bild setzen (beim Start / Neuladen)
#    wallpaper.sh set <bild> bestimmtes Bild setzen (Ordner wird gemerkt)
#    wallpaper.sh select     Auswahl mit Vorschau und Pfadsuche (⌘⌃W)
#    wallpaper.sh random     zufälliges Bild (⌘⇧W)
#    wallpaper.sh rotate     automatischen Wechsel an/aus (⌘⌥W)
#    wallpaper.sh dirs       alle Hintergrund-Ordner ausgeben
#    wallpaper.sh add-dir <ordner>  Ordner dauerhaft zu den Hintergrund-Ordnern
#    wallpaper.sh list       alle Bilder ausgeben (Auswahlfenster, test.sh)
#  Bilder: ~/.config/i3-apple/wallpapers, ~/Bilder/Hintergründe und jeder
#  Ordner, aus dem schon einmal ein Bild gewählt wurde
#  (~/.config/i3-apple/wallpaper-dirs).
# ═══════════════════════════════════════════════════════════════════
SETTINGS="$HOME/.config/i3-apple"
CURRENT="$SETTINGS/current-wallpaper"
EXTRA_DIRS="$SETTINGS/wallpaper-dirs"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL=600
mkdir -p "$RUNTIME" "$SETTINGS/wallpapers"

wall_dirs() {
  local pics d
  {
    echo "$SETTINGS/wallpapers"
    pics=$(xdg-user-dir PICTURES 2>/dev/null)
    [[ -z $pics || $pics == "$HOME" ]] && pics="$HOME/Pictures"   # ohne Bilder-Ordner meldet es $HOME
    for d in "$pics/Hintergründe" "$pics/Wallpapers" "$pics/wallpapers"; do echo "$d"; done
    [[ -f $EXTRA_DIRS ]] && cat "$EXTRA_DIRS"
  } | while IFS= read -r d; do [[ -n $d && -d $d ]] && realpath -- "$d"; done | awk '!seen[$0]++'
}

all_walls() {
  local d
  while IFS= read -r d; do
    find "$d" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null
  done < <(wall_dirs) | sort -u
}

# Ordner merken, damit „zufällig“ und die Auswahl ihn künftig kennen
#   remember_dir <bild>          Ordner des Bildes
#   remember_dir --dir <ordner>  der Ordner selbst (Auswahlfenster: „Ordner hinzufügen“)
remember_dir() {
  local dir
  if [[ $1 == --dir ]]; then dir=$(realpath -- "$2") || return
  else dir=$(realpath -- "$(dirname -- "$1")") || return; fi
  [[ -d $dir ]] || return
  wall_dirs | grep -qxF -- "$dir" && return
  printf '%s\n' "$dir" >> "$EXTRA_DIRS"
}

# swaybg läuft als eigener Prozess: Sway-Neuladen lässt ihn in Ruhe, neue
# Bildschirme bekommen das Bild automatisch. Erst das neue Bild starten,
# dann das alte beenden – so flackert nichts.
#   start_bg <bild>   oder   start_bg '#rrggbb' (einfarbig)
start_bg() {
  local pidfile="$RUNTIME/swaybg.pid" new old
  local -a args=(-m fill -i "$1")
  old=$(cat "$pidfile" 2>/dev/null)
  [[ $1 == \#* ]] && args=(-c "$1")
  rm -f "$pidfile.new"
  setsid -f bash -c 'p=$1; shift; echo $$ > "$p"; exec swaybg "$@"' _ "$pidfile.new" "${args[@]}" >/dev/null 2>&1
  for _ in $(seq 40); do [[ -s $pidfile.new ]] && break; sleep 0.05; done
  new=$(cat "$pidfile.new" 2>/dev/null)
  if [[ -n $new ]]; then mv -f "$pidfile.new" "$pidfile"; else rm -f "$pidfile" "$pidfile.new"; fi
  printf '%s\n' "$1" > "$RUNTIME/swaybg.image"
  # Alle übrigen swaybg beenden – auch solche, deren PID nie vermerkt wurde
  # (sonst blieben zwei swaybg übereinander bestehen). Ist die neue PID
  # unbekannt, nur den bisher vermerkten, um den neuen nicht zu treffen.
  (
    sleep 0.6
    if [[ -n $new ]]; then
      pgrep -u "$USER" -x swaybg | while read -r p; do
        [[ $p == "$new" ]] || kill "$p" 2>/dev/null
      done
    elif [[ -n $old ]]; then
      kill "$old" 2>/dev/null
    fi
  ) >/dev/null 2>&1 &
}

apply() {
  [[ -f $1 ]] || return 1
  local old
  old=$(cat "$RUNTIME/swaybg.pid" 2>/dev/null)
  if [[ -n $old ]] && kill -0 "$old" 2>/dev/null && [[ $(cat "$RUNTIME/swaybg.image" 2>/dev/null) == "$1" ]]; then
    return 0   # läuft schon mit diesem Bild (z. B. nach Sway-Neuladen)
  fi
  start_bg "$1"
  printf '%s\n' "$1" > "$CURRENT"
}

# Auswahl ohne GTK (Ersatz): rofi-Raster, eigene Eingabe = Pfad
select_rofi() {
  local walls choice idx
  mapfile -t walls < <(all_walls)
  # „i s“: Index der Auswahl (eindeutig, auch bei gleichen Dateinamen in
  # verschiedenen Ordnern) und Text; bei eigener Eingabe ist der Index -1
  choice=$(for w in "${walls[@]}"; do printf '%s\0icon\x1f%s\n' "${w##*/}" "$w"; done |
    rofi -dmenu -i -p "" -format 'i s' -show-icons \
      -mesg "Bildname suchen oder Pfad eingeben (Strg+Enter übernimmt den Pfad)" \
      -theme-str 'window { width: 820px; } listview { columns: 4; lines: 3; } element { orientation: vertical; padding: 10px; } element-icon { size: 150px; } element-text { horizontal-align: 0.5; } entry { placeholder: "Hintergrundbild wählen"; }')
  [[ -n $choice ]] || return
  idx=${choice%% *} choice=${choice#* }
  if [[ $idx =~ ^[0-9]+$ ]] && (( idx < ${#walls[@]} )); then
    apply "${walls[$idx]}"; return
  fi
  choice=${choice/#\~/$HOME}
  [[ -f $choice ]] || return
  choice=$(realpath -- "$choice")
  remember_dir "$choice"; apply "$choice"
}

case ${1:-} in
  set)
    [[ -f ${2:-} ]] || exit 1
    file=$(realpath -- "$2")
    remember_dir "$file"
    apply "$file" ;;
  dirs)   wall_dirs ;;
  add-dir)
    [[ -d ${2:-} ]] || exit 1
    remember_dir --dir "$2" ;;
  list)   all_walls ;;
  random)
    mapfile -t walls < <(all_walls)
    (( ${#walls[@]} )) && apply "${walls[RANDOM % ${#walls[@]}]}" ;;
  select)
    # GTK-Fenster mit Pfadsuche. Fehlt python3-gi oder scheitert das Fenster,
    # gibt es eine Mitteilung (Details im Protokoll) und das rofi-Raster.
    log="$RUNTIME/wallpaper-picker.log"
    if python3 -c 'import gi, cairo; gi.require_version("Gtk", "3.0")' 2>"$log"; then
      python3 "$SCRIPTS/wallpaper-picker.py" 2>"$log" && exit 0
      notify-send -a "Hintergrund" "Auswahlfenster konnte nicht geöffnet werden" \
        "$(grep -v '^ ' "$log" | tail -n1)  ·  Details: $log"
    else
      notify-send -a "Hintergrund" "Auswahlfenster nicht verfügbar" \
        "python3-gi / python3-gi-cairo fehlt – es folgt die einfache Auswahl."
    fi
    select_rofi ;;
  rotate)
    pidfile="$RUNTIME/wallpaper-rotate.pid"
    if [[ -f $pidfile ]] && kill "$(cat "$pidfile")" 2>/dev/null; then
      rm -f "$pidfile"
      notify-send -a "Hintergrund" "Automatischer Wechsel aus"
    else
      setsid -f bash -c "echo \$\$ > '$pidfile'; while sleep $INTERVAL; do '$0' random; done" >/dev/null 2>&1
      notify-send -a "Hintergrund" "Automatischer Wechsel an" "Alle $((INTERVAL / 60)) Minuten ein neues Bild."
    fi ;;
  *)
    apply "$(cat "$CURRENT" 2>/dev/null)" && exit 0
    first=$(all_walls | head -n1)
    [[ -n $first ]] && apply "$first" && exit 0
    # Kein Bild vorhanden: einfarbiger Hintergrund (vermerkt wie jedes Bild)
    [[ $(cat "$RUNTIME/swaybg.image" 2>/dev/null) == '#1e2a44' ]] &&
      kill -0 "$(cat "$RUNTIME/swaybg.pid" 2>/dev/null)" 2>/dev/null && exit 0
    start_bg '#1e2a44' ;;
esac
