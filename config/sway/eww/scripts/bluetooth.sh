#!/usr/bin/env bash
# Bluetooth über bluetoothctl.
#   bluetooth.sh status | devices | toggle | connect <MAC>
source "$(dirname "$0")/lib.sh"
export LC_ALL=C.UTF-8

MAC_RE='^([0-9A-F]{2}:){5}[0-9A-F]{2}$'

# bluetoothctl hängt ohne bluetoothd endlos – daher immer mit Timeout
btctl() { timeout 3 bluetoothctl "$@" 2>/dev/null; }

# „devices Paired|Connected“ filtert erst ab BlueZ 5.65 – ältere Versionen
# ignorieren das Argument und listen alle bekannten Geräte. Dann wird jedes
# Gerät einzeln gefragt.
bluez_filters() {
  local v
  v=$(bluetoothctl --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)
  [[ $v =~ ^([0-9]+)\.([0-9]+)$ ]] || return 1
  (( BASH_REMATCH[1] > 5 || (BASH_REMATCH[1] == 5 && BASH_REMATCH[2] >= 65) ))
}
devices_where() { # devices_where Paired|Connected → MAC-Adressen
  local mac
  if bluez_filters; then
    btctl devices "$1" | awk '$1 == "Device" { print $2 }'
    return
  fi
  btctl devices | awk '$1 == "Device" { print $2 }' | while read -r mac; do
    btctl info "$mac" | grep -qE "^[[:space:]]*$1: yes" && echo "$mac"
  done
}

status() {
  local show powered=false connected=0 icon label
  show=$(btctl show)
  if ! grep -q 'Powered:' <<<"$show"; then
    echo '{"available":false,"powered":false,"connected":0,"icon":"bluetooth-disabled-symbolic","label":""}'
    return
  fi
  grep -q 'Powered: yes' <<<"$show" && powered=true
  if $powered; then
    connected=$(devices_where Connected | grep -c .)
  fi
  if ! $powered;        then icon=bluetooth-disabled-symbolic; label="Bluetooth ist ausgeschaltet"
  elif (( connected )); then icon=bluetooth-active-symbolic;   label="$connected Gerät(e) verbunden"
  else                       icon=bluetooth-active-symbolic;   label="Eingeschaltet"; fi

  jq -nc --argjson powered "$powered" --argjson connected "$connected" --arg icon "$icon" --arg label "$label" \
    '{available: true, powered: $powered, connected: $connected, icon: $icon, label: $label}'
}

# BlueZ liefert Freedesktop-Icon-Namen (audio-headset, input-mouse …) → symbolische Variante
device_icon() {
  if [[ $1 =~ ^[a-z-]+$ ]]; then echo "$1-symbolic"; else echo bluetooth-active-symbolic; fi
}

devices() {
  local mac info name connected type batt
  devices_where Paired | while read -r mac; do
    [[ $mac =~ $MAC_RE ]] || continue
    info=$(btctl info "$mac")
    name=$(sed -n 's/^\s*Alias: //p' <<<"$info" | head -n1)
    grep -q 'Connected: yes' <<<"$info" && connected=true || connected=false
    type=$(sed -n 's/^\s*Icon: //p' <<<"$info" | head -n1)
    batt=$(sed -n 's/^\s*Battery Percentage: .*(\([0-9]*\)).*/\1/p' <<<"$info" | head -n1)
    jq -nc --arg mac "$mac" --arg name "${name:-$mac}" --argjson connected "$connected" \
           --arg icon "$(device_icon "$type")" --arg battery "$batt" \
      '{mac: $mac, name: $name, connected: $connected, icon: $icon, battery: $battery}'
  done | jq -sc 'sort_by((.connected | not), (.name | ascii_downcase))'
}

refresh() {
  eww_ update bt="$(status)"
  popup_open bluetooth && eww_ update bt_devices="$(devices)"
}

toggle() {
  if btctl show | grep -q 'Powered: yes'; then
    btctl power off >/dev/null
  else
    rfkill unblock bluetooth 2>/dev/null
    btctl power on >/dev/null
  fi
  sleep 0.5
  refresh
}

connect() {
  local mac=$1 name
  [[ $mac =~ $MAC_RE ]] || exit 1
  name=$(btctl info "$mac" | sed -n 's/^\s*Alias: //p' | head -n1)
  if btctl info "$mac" | grep -q 'Connected: yes'; then
    btctl disconnect "$mac" >/dev/null
    notify bluetooth "Getrennt" "$name"
  else
    notify bluetooth "Verbinde mit „$name“ …"
    if timeout 15 bluetoothctl connect "$mac" 2>/dev/null | grep -q 'Connection successful'; then
      notify bluetooth "Verbunden" "$name"
    else
      notify bluetooth "Verbindung fehlgeschlagen" "$name ist nicht erreichbar."
    fi
  fi
  refresh
}

case $1 in
  status)  status ;;
  devices) devices ;;
  toggle)  toggle ;;
  connect) connect "$2" ;;
  *) echo "Aufruf: $0 status|devices|toggle|connect <MAC>" >&2; exit 1 ;;
esac
