#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Bildschirmaufnahme (wf-recorder)
#    record.sh start <bereich|bildschirm> [ohne|system|mikro]
#    record.sh stop          Aufnahme beenden und speichern
#    record.sh toggle        läuft eine → beenden, sonst Bildschirm ohne Ton (⌘⌥R)
#    record.sh status        JSON für die Menüleiste: {"active":…, "time":"m:ss"}
#  Videos: ~/Videos/Bildschirmaufnahmen (XDG-Ordner „Videos“), Pfad landet
#  nach dem Beenden in der Zwischenablage.
# ═══════════════════════════════════════════════════════════════════
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
PIDF="$RUNTIME/record.pid"
INFO="$RUNTIME/record.info"     # Zeile 1: Datei, Zeile 2: Startzeit (Unixzeit)
LOG="$RUNTIME/record.log"
EWW_DIR="$HOME/.config/sway/eww"
EWW_BIN="$(command -v eww 2>/dev/null || echo "$HOME/.local/bin/eww")"

note() { notify-send -a "Bildschirmaufnahme" -h string:x-dunst-stack-tag:record "$@"; }
recording() { [[ -f $PIDF ]] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; }
bar_update() { "$EWW_BIN" -c "$EWW_DIR" update recording="$(status)" >/dev/null 2>&1; }

status() {
  if recording && [[ -f $INFO ]]; then
    local t0 s
    t0=$(sed -n 2p "$INFO"); s=$(( $(date +%s) - ${t0:-$(date +%s)} ))
    printf '{"active":true,"time":"%d:%02d"}\n' $((s / 60)) $((s % 60))
  else
    echo '{"active":false,"time":""}'
  fi
}

start() { # start <bereich|bildschirm> [ohne|system|mikro]
  if recording; then stop; return; fi
  command -v wf-recorder >/dev/null || { note "Aufnahme nicht möglich" "wf-recorder ist nicht installiert (sway/install.sh)."; exit 1; }
  local target=${1:-bildschirm} audio=${2:-ohne} args=() g out dir file dev
  case $target in
    bereich)
      g=$(slurp -d -b 00000066 -c ff453aff -w 2) || exit 0
      args+=(-g "$g") ;;
    *)
      out=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.focused) | .name')
      [[ -n $out ]] && args+=(-o "$out") ;;
  esac
  case $audio in
    system) dev=$(pactl get-default-sink 2>/dev/null) && [[ -n $dev ]] && args+=("--audio=$dev.monitor") ;;
    mikro)  dev=$(pactl get-default-source 2>/dev/null) && [[ -n $dev ]] && args+=("--audio=$dev") ;;
  esac

  dir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")"
  [[ $dir == "$HOME" || -z $dir ]] && dir="$HOME/Videos"
  dir="$dir/Bildschirmaufnahmen"
  mkdir -p "$dir"
  file="$dir/Bildschirmaufnahme $(date '+%Y-%m-%d um %H.%M.%S').mp4"

  note "Aufnahme beginnt in 3 Sekunden" "Beenden: Super + Alt + R oder roter Punkt in der Menüleiste"
  sleep 3
  rm -f "$PIDF"
  setsid -f bash -c 'echo $$ > "$1"; shift; exec wf-recorder "$@"' _ "$PIDF" -f "$file" "${args[@]}" \
    >"$LOG" 2>&1 </dev/null
  for _ in $(seq 20); do [[ -s $PIDF ]] && break; sleep 0.05; done
  printf '%s\n%s\n' "$file" "$(date +%s)" > "$INFO"
  sleep 0.5
  if ! recording; then
    note "Aufnahme konnte nicht starten" "$(tail -n 2 "$LOG")"
    rm -f "$PIDF" "$INFO"
  fi
  bar_update
}

stop() {
  if ! recording; then rm -f "$PIDF" "$INFO"; bar_update; return; fi
  local pid file
  pid=$(cat "$PIDF")
  file=$(sed -n 1p "$INFO" 2>/dev/null)
  kill -INT "$pid" 2>/dev/null           # wf-recorder schreibt die Datei sauber zu Ende
  for _ in $(seq 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$pid" 2>/dev/null && kill -TERM "$pid"
  rm -f "$PIDF" "$INFO"
  bar_update
  if [[ -s $file ]]; then
    printf 'file://%s\n' "$file" | wl-copy -t text/uri-list
    note "Bildschirmaufnahme gespeichert" "${file/#$HOME/\~}  ·  Datei in der Zwischenablage"
  else
    note "Aufnahme fehlgeschlagen" "$(tail -n 2 "$LOG")"
  fi
}

case ${1:-} in
  start)  start "${2:-bildschirm}" "${3:-ohne}" ;;
  stop)   stop ;;
  toggle) if recording; then stop; else start bildschirm ohne; fi ;;
  status) status ;;
  *) echo "Aufruf: $0 start <bereich|bildschirm> [ohne|system|mikro] | stop | toggle | status" >&2; exit 1 ;;
esac
