#!/usr/bin/env bash
# WLAN über NetworkManager.
#   wifi.sh status | list [auto|yes|no] | toggle | connect-index <n>
# Netzwerke werden per Index angesprochen, damit SSIDs (fremde Daten!)
# nie in Shell-Befehle der Leiste eingesetzt werden.
source "$(dirname "$0")/lib.sh"
export LC_ALL=C.UTF-8

CACHE="$RUNTIME/wifi-list.json"

# nmcli -t maskiert „:“ als „\:“ und „\“ als „\\“
unescape() {
  local s=${1//\\\\/$'\x01'}
  s=${s//\\:/:}
  printf '%s' "${s//$'\x01'/\\}"
}

# Gespeicherte WLAN-Profile als SSID<TAB>UUID. Verglichen wird über die SSID –
# der Profilname kann davon abweichen (z. B. „Büro“ für „FRITZ!Box 7590 XY“).
known_profiles() {
  local uuid type ssid
  nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r uuid type; do
    [[ $type == 802-11-wireless ]] || continue
    ssid=$(nmcli -g 802-11-wireless.ssid connection show uuid "$uuid" 2>/dev/null)
    [[ -n $ssid ]] && printf '%s\t%s\n' "$(unescape "$ssid")" "$uuid"
  done
}

signal_icon() {
  if   (( $1 >= 80 )); then echo network-wireless-signal-excellent-symbolic
  elif (( $1 >= 55 )); then echo network-wireless-signal-good-symbolic
  elif (( $1 >= 30 )); then echo network-wireless-signal-ok-symbolic
  else                      echo network-wireless-signal-weak-symbolic; fi
}

status() {
  local radio line rest ssid="" signal=0 enabled=false connected=false wired=false icon label
  radio=$(nmcli -t -f WIFI radio 2>/dev/null)
  [[ $radio == enabled ]] && enabled=true
  nmcli -t -f TYPE,STATE device 2>/dev/null | grep -q '^ethernet:connected' && wired=true

  if $enabled; then
    line=$(nmcli -t -f ACTIVE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null | grep -m1 '^yes:')
    if [[ -n $line ]]; then
      rest=${line#yes:}
      signal=${rest%%:*}
      ssid=$(unescape "${rest#*:}")
      connected=true
    fi
  fi
  [[ $signal =~ ^[0-9]+$ ]] || signal=0

  if $connected; then icon=$(signal_icon "$signal");                  label="Verbunden mit $ssid"
  elif $wired;   then icon=network-wired-symbolic;                    label="Kabelgebunden verbunden"
  elif $enabled; then icon=network-wireless-signal-none-symbolic;     label="Nicht verbunden"
  else                icon=network-wireless-disabled-symbolic;        label="WLAN ist ausgeschaltet"; fi

  jq -nc --argjson enabled "$enabled" --argjson connected "$connected" --argjson wired "$wired" \
         --arg ssid "$ssid" --argjson signal "$signal" --arg icon "$icon" --arg label "$label" \
    '{enabled: $enabled, connected: $connected, wired: $wired, ssid: $ssid, signal: $signal, icon: $icon, label: $label}'
}

list() {
  local profiles inuse signal security ssid active uuid
  profiles=$(known_profiles)

  nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "${1:-auto}" 2>/dev/null |
    while IFS=: read -r inuse signal security ssid; do
      ssid=$(unescape "$ssid")
      [[ -z $ssid ]] && continue
      [[ $signal =~ ^[0-9]+$ ]] || signal=0
      [[ $inuse == '*' ]] && active=true || active=false
      uuid=$(awk -F'\t' -v s="$ssid" '$1 == s { print $2; exit }' <<<"$profiles")
      jq -nc --arg ssid "$ssid" --argjson signal "$signal" --arg sec "$security" \
             --argjson active "$active" --arg uuid "$uuid" \
        '{ssid: $ssid, signal: $signal, secure: ($sec != "" and $sec != "--"), active: $active,
          known: ($uuid != ""), uuid: $uuid}'
    done |
    jq -sc '
      group_by(.ssid)
      | map(max_by(.signal) + {active: (map(.active) | any)})
      | sort_by((.active | not), (.known | not), -.signal)
      | .[:12]
      | to_entries
      | map(.value + {
          idx: .key,
          icon: ("network-wireless-signal-"
                 + (if .value.signal >= 80 then "excellent" elif .value.signal >= 55 then "good"
                    elif .value.signal >= 30 then "ok" else "weak" end)
                 + "-symbolic")
        })' > "$CACHE.tmp"
  mv "$CACHE.tmp" "$CACHE"
  cat "$CACHE"
}

refresh() {
  eww_ update wifi="$(status)"
  popup_open wifi && eww_ update wifi_list="$(list no)"
}

ask_password() { # ask_password <ssid> [hinweis]
  local esc
  esc=$(printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
  rofi -dmenu -password -p "" -l 0 \
    -mesg "Das WLAN-Netzwerk <b>$esc</b> benötigt ein Passwort.${2:+$'\n'$2}" \
    -theme-str 'entry { placeholder: "Passwort"; } icon-search { filename: "dialog-password"; } listview { enabled: false; }' \
    </dev/null
}

# Liegt das Passwort in KWallet? Plasma speichert WLAN-Passwörter dort
# (psk-flags 1 = „agent-owned“). Ohne laufendes Plasma kann NetworkManager
# sie nicht lesen – die Verbindung scheitert dann mit „Secrets were required“.
in_kwallet() { # in_kwallet <uuid>
  local flags
  flags=$(nmcli -g 802-11-wireless-security.psk-flags connection show uuid "$1" 2>/dev/null)
  [[ -n $flags && $flags != 0* ]]
}

# Passwort einmal abfragen und systemweit speichern (psk-flags 0).
# Danach verbindet sich das Netzwerk in Sway und Plasma automatisch.
migrate_kwallet() { # migrate_kwallet <ssid> <uuid>
  local ssid=$1 uuid=$2 pw
  "$EWW_DIR/scripts/popup.sh" close
  pw=$(ask_password "$ssid" "In Plasma gespeichert (KWallet) – einmal eingeben, dann kennen es Sway und Plasma.") || return 1
  [[ -n $pw ]] || return 1
  notify wifi "Verbinde mit „$ssid“ …"
  nmcli connection modify uuid "$uuid" 802-11-wireless-security.psk-flags 0 \
    802-11-wireless-security.psk "$pw" >/dev/null 2>&1 &&
    nmcli --wait 30 connection up uuid "$uuid" >/dev/null 2>&1
}

connect_index() {
  [[ $1 =~ ^[0-9]+$ ]] || exit 1
  local entry ssid secure known active uuid iface pw
  entry=$(jq -c --argjson i "$1" '.[$i] // empty' "$CACHE" 2>/dev/null)
  [[ -n $entry ]] || exit 1
  ssid=$(jq -r .ssid <<<"$entry")
  secure=$(jq -r .secure <<<"$entry")
  known=$(jq -r .known <<<"$entry")
  active=$(jq -r .active <<<"$entry")
  uuid=$(jq -r '.uuid // ""' <<<"$entry")
  [[ $uuid =~ ^[0-9a-fA-F-]+$ ]] || { uuid=""; known=false; }

  if [[ $active == true ]]; then
    iface=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')
    nmcli device disconnect "$iface" >/dev/null 2>&1
    notify wifi "WLAN getrennt" "$ssid"
  elif [[ $known == true || $secure == false ]]; then
    notify wifi "Verbinde mit „$ssid“ …"
    if { [[ -n $uuid ]] && nmcli --wait 20 connection up uuid "$uuid" >/dev/null 2>&1; } ||
       nmcli --wait 20 device wifi connect "$ssid" >/dev/null 2>&1; then
      notify wifi "Verbunden mit „$ssid“"
    elif [[ $known == true && $secure == true ]] && in_kwallet "$uuid"; then
      if migrate_kwallet "$ssid" "$uuid"; then
        notify wifi "Verbunden mit „$ssid“"
      else
        notify wifi "Verbindung fehlgeschlagen" "Passwort falsch oder Netzwerk nicht erreichbar."
      fi
    else
      notify wifi "Verbindung fehlgeschlagen" "„$ssid“ ist nicht erreichbar."
    fi
  else
    "$EWW_DIR/scripts/popup.sh" close
    pw=$(ask_password "$ssid") || exit 0
    [[ -n $pw ]] || exit 0
    notify wifi "Verbinde mit „$ssid“ …"
    if nmcli --wait 30 device wifi connect "$ssid" password "$pw" >/dev/null 2>&1; then
      notify wifi "Verbunden mit „$ssid“"
    else
      notify wifi "Verbindung fehlgeschlagen" "Passwort falsch oder Netzwerk nicht erreichbar."
    fi
  fi
  refresh
}

toggle() {
  if [[ $(nmcli -t -f WIFI radio) == enabled ]]; then
    nmcli radio wifi off
  else
    nmcli radio wifi on
  fi
  sleep 0.5
  refresh
}

case $1 in
  status)        status ;;
  list)          list "${2:-auto}" ;;
  toggle)        toggle ;;
  connect-index) connect_index "$2" ;;
  *) echo "Aufruf: $0 status|list|toggle|connect-index <n>" >&2; exit 1 ;;
esac
