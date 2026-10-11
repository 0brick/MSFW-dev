#!/usr/bin/env bash
# Lautstärke & Mikrofon über PipeWire/PulseAudio (pactl).
#   volume.sh listen | status | set <0-100> | up | down | mute | scroll up|down
#             mic-set <0-100> | mic-mute | sinks | sink <id>
source "$(dirname "$0")/lib.sh"
export LC_ALL=C.UTF-8

pct() { # Zahl aus eww (evtl. „42.5“) → ganzzahlig 0..100
  local v=${1%%.*}
  [[ $v =~ ^[0-9]+$ ]] || v=0
  (( v > 100 )) && v=100
  echo "$v"
}

status() {
  local vol mic muted=false mic_muted=false icon mic_icon
  vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oE '[0-9]+%' | head -n1 | tr -d %)
  mic=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -oE '[0-9]+%' | head -n1 | tr -d %)
  pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q yes && muted=true
  pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -q yes && mic_muted=true
  vol=${vol:-0}; mic=${mic:-0}

  if $muted || (( vol == 0 )); then icon=audio-volume-muted-symbolic
  elif (( vol < 34 ));         then icon=audio-volume-low-symbolic
  elif (( vol < 67 ));         then icon=audio-volume-medium-symbolic
  elif (( vol <= 100 ));       then icon=audio-volume-high-symbolic
  else                              icon=audio-volume-overamplified-symbolic; fi

  if $mic_muted; then mic_icon=microphone-sensitivity-muted-symbolic
  else                mic_icon=audio-input-microphone-symbolic; fi

  jq -nc --argjson volume "$vol" --argjson muted "$muted" --argjson mic "$mic" \
         --argjson mic_muted "$mic_muted" --arg icon "$icon" --arg mic_icon "$mic_icon" \
    '{volume: $volume, muted: $muted, mic: $mic, mic_muted: $mic_muted, icon: $icon, mic_icon: $mic_icon}'
}

listen() {
  while true; do
    status
    pactl subscribe 2>/dev/null |
      grep --line-buffered -E "'change' on (sink|source|server)" |
      while read -r _; do status; done
    sleep 1 # Audio-Server neu gestartet
  done
}

osd() { # kleine Einblendung über dunst (bei Medientasten)
  local s v m
  s=$(status); v=$(jq -r .volume <<<"$s"); m=$(jq -r .muted <<<"$s")
  if [[ $m == true ]]; then
    notify-send -a osd -u low -t 1200 -h string:x-dunst-stack-tag:volume -h int:value:0 "Ton aus"
  else
    notify-send -a osd -u low -t 1200 -h string:x-dunst-stack-tag:volume -h "int:value:$v" "Lautstärke  $v %"
  fi
}

change() { # change +5 | -5
  local cur new
  cur=$(status | jq .volume)
  new=$(( cur + $1 ))
  (( new < 0 )) && new=0
  # über 100 % nicht weiter anheben – aber auch nicht auf 100 % absenken,
  # wenn die Lautstärke (z. B. aus pavucontrol) schon darüber liegt
  (( new > 100 )) && new=$(( cur > 100 ? cur : 100 ))
  pactl set-sink-mute @DEFAULT_SINK@ 0
  pactl set-sink-volume @DEFAULT_SINK@ "${new}%"
}

sinks() {
  local def
  def=$(pactl get-default-sink 2>/dev/null)
  pactl -f json list sinks 2>/dev/null |
    jq -c --arg def "$def" '[.[] | {id: .index, name: (.description // .name), default: (.name == $def)}]' 2>/dev/null ||
    echo '[]'
}

set_sink() {
  local id=$1 name
  [[ $id =~ ^[0-9]+$ ]] || exit 1
  name=$(pactl -f json list sinks | jq -r --argjson id "$id" '.[] | select(.index == $id) | .name')
  [[ -n $name ]] || exit 1
  pactl set-default-sink "$name"
  pactl list short sink-inputs | while read -r input _; do
    pactl move-sink-input "$input" "$name" 2>/dev/null
  done
  eww_ update sinks="$(sinks)"
}

case $1 in
  listen)   listen ;;
  status)   status ;;
  set)      pactl set-sink-mute @DEFAULT_SINK@ 0; pactl set-sink-volume @DEFAULT_SINK@ "$(pct "$2")%" ;;
  up)       change +5; osd ;;
  down)     change -5; osd ;;
  mute)     pactl set-sink-mute @DEFAULT_SINK@ toggle; [[ $2 == --osd ]] && osd ;;
  scroll)   [[ $2 == up ]] && change +5 || change -5 ;;
  mic-set)  pactl set-source-mute @DEFAULT_SOURCE@ 0; pactl set-source-volume @DEFAULT_SOURCE@ "$(pct "$2")%" ;;
  mic-mute) pactl set-source-mute @DEFAULT_SOURCE@ toggle ;;
  sinks)    sinks ;;
  sink)     set_sink "$2" ;;
  *) echo "Aufruf: $0 listen|status|set|up|down|mute|scroll|mic-set|mic-mute|sinks|sink" >&2; exit 1 ;;
esac
