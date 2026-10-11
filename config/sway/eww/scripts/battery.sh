#!/usr/bin/env bash
# Batterie, Energiemodus & Bildschirmhelligkeit.
#   battery.sh status | details | profiles | profile <name> | toggle-pct
#              brightness <0-100> | brightness-up | brightness-down
source "$(dirname "$0")/lib.sh"
export LC_ALL=C.UTF-8

# Systembatterie finden (Peripherie-Akkus wie Mäuse ausschließen)
BAT=""
for ps in /sys/class/power_supply/*; do
  [[ $(cat "$ps/type" 2>/dev/null) == Battery ]] || continue
  [[ $(cat "$ps/scope" 2>/dev/null) == Device ]] && continue
  BAT=$ps; break
done

rd() { local v; v=$(cat "$BAT/$1" 2>/dev/null); echo "${v:-0}"; }

plugged() {
  local ps
  for ps in /sys/class/power_supply/*; do
    case $(cat "$ps/type" 2>/dev/null) in
      Mains|USB) [[ $(cat "$ps/online" 2>/dev/null) == 1 ]] && return 0 ;;
    esac
  done
  return 1
}

status() {
  if [[ -z $BAT ]]; then
    echo '{"available":false,"capacity":0,"state":"normal","plugged":false,"icon":"battery-missing-symbolic"}'
    return
  fi
  local cap st prof state=normal on_ac=false icon level
  cap=$(rd capacity)
  st=$(cat "$BAT/status" 2>/dev/null)
  plugged && on_ac=true
  prof=$(powerprofilesctl get 2>/dev/null)

  if [[ $st == Charging ]];               then state=charging
  elif (( cap <= 20 )) && ! $on_ac;       then state=low
  elif [[ $prof == power-saver ]];        then state=saver; fi

  # Theme-Icons gibt es in 10er-Stufen: battery-level-70(-charging)-symbolic
  level=$(( (cap + 5) / 10 * 10 ))
  (( level > 100 )) && level=100
  if [[ $st == Full ]] && $on_ac;  then icon=battery-level-100-charged-symbolic
  elif [[ $st == Charging ]] || $on_ac; then icon="battery-level-$level-charging-symbolic"
  else                                   icon="battery-level-$level-symbolic"; fi

  jq -nc --argjson capacity "$cap" --arg state "$state" --argjson plugged "$on_ac" --arg icon "$icon" \
    '{available: true, capacity: $capacity, state: $state, plugged: $plugged, icon: $icon}'
}

brightness_get() {
  command -v brightnessctl >/dev/null || return 1
  brightnessctl -m -c backlight 2>/dev/null | head -n1 | cut -d, -f4 | tr -d %
}

details() {
  local cap st en full design pw cyc v json b bavail=false
  [[ -n $BAT ]] || { echo '{"subtitle":"Keine Batterie","health":"–","cycles":"–","power":"–","energy":"–","brightness_available":false,"brightness":0}'; return; }
  cap=$(rd capacity)
  st=$(cat "$BAT/status" 2>/dev/null)
  cyc=$(rd cycle_count)

  if [[ -r $BAT/energy_now ]]; then          # µWh
    en=$(rd energy_now); full=$(rd energy_full); design=$(rd energy_full_design)
  else                                        # µAh → µWh
    v=$(rd voltage_min_design)
    en=$(( $(rd charge_now) * v / 1000000 ))
    full=$(( $(rd charge_full) * v / 1000000 ))
    design=$(( $(rd charge_full_design) * v / 1000000 ))
  fi
  if [[ -r $BAT/power_now ]]; then            # µW
    pw=$(rd power_now)
  else
    pw=$(( $(rd current_now) * $(rd voltage_now) / 1000000 ))
  fi
  pw=${pw#-}

  json=$(awk -v st="$st" -v en="$en" -v full="$full" -v design="$design" -v pw="$pw" -v cyc="$cyc" '
    function de(x,   s) { s = sprintf("%.1f", x); sub(/\./, ",", s); return s }
    function hm(h,   m) { m = int(h * 60 + 0.5); return sprintf("%d:%02d Std.", int(m / 60), m % 60) }
    BEGIN {
      if (st == "Charging")          { sub_ = "Wird geladen"; if (pw > 0 && full > en) sub_ = sub_ " · voll in " hm((full - en) / pw) }
      else if (st == "Discharging")  { sub_ = "Akkubetrieb";  if (pw > 0) sub_ = sub_ " · noch " hm(en / pw) }
      else if (st == "Full")         { sub_ = "Vollständig geladen" }
      else if (st == "Not charging") { sub_ = "Angeschlossen · wird nicht geladen" }
      else                           { sub_ = st }
      health = (design > 0) ? sprintf("%d %%", full / design * 100 + 0.5) : "–"
      cycles = (cyc > 0) ? cyc : "–"
      power  = (pw > 0) ? de(pw / 1e6) " W" : "–"
      energy = (full > 0) ? de(en / 1e6) " / " de(full / 1e6) " Wh" : "–"
      printf "{\"subtitle\":\"%s\",\"health\":\"%s\",\"cycles\":\"%s\",\"power\":\"%s\",\"energy\":\"%s\"}\n", sub_, health, cycles, power, energy
    }')

  if b=$(brightness_get) && [[ $b =~ ^[0-9]+$ ]]; then bavail=true; else b=0; fi
  jq -c --argjson ba "$bavail" --argjson b "$b" '. + {brightness_available: $ba, brightness: $b}' <<<"$json"
}

profiles() {
  command -v powerprofilesctl >/dev/null || { echo '[]'; return; }
  powerprofilesctl list 2>/dev/null |
    sed -nE 's/^(\*| ) ([a-z-]+):$/\1\2/p' |
    jq -Rsc '
      split("\n") | map(select(length > 0)
        | {name: (ltrimstr("*") | ltrimstr(" ")), active: startswith("*")})
      | map(. + {
          label: ({"power-saver": "Sparen", "balanced": "Ausgewogen", "performance": "Leistung"}[.name] // .name),
          order: ({"power-saver": 0, "balanced": 1, "performance": 2}[.name] // 9)
        })
      | sort_by(.order)'
}

set_profile() {
  case $1 in power-saver|balanced|performance) ;; *) exit 1 ;; esac
  powerprofilesctl set "$1" || notify battery "Energiemodus nicht verfügbar" "$1"
  eww_ update power_profiles="$(profiles)" battery="$(status)"
}

set_brightness() {
  local v=${1%%.*}
  [[ $v =~ ^[0-9]+$ ]] || exit 1
  (( v < 1 )) && v=1
  (( v > 100 )) && v=100
  brightnessctl -q -c backlight set "${v}%"
}

step_brightness() {
  brightnessctl -q -c backlight set "$1"
  local b; b=$(brightness_get)
  notify-send -a osd -u low -t 1200 -h string:x-dunst-stack-tag:brightness -h "int:value:$b" "Helligkeit  $b %"
}

toggle_pct() {
  local cur new
  cur=$(eww_ get bat_show_pct)
  [[ $cur == true ]] && new=false || new=true
  echo "$new" > "$SETTINGS/bat_show_pct"
  eww_ update bat_show_pct="$new"
}

case $1 in
  status)          status ;;
  details)         details ;;
  profiles)        profiles ;;
  profile)         set_profile "$2" ;;
  toggle-pct)      toggle_pct ;;
  brightness)      set_brightness "$2" ;;
  brightness-up)   step_brightness 5%+ ;;
  brightness-down) step_brightness 5%- ;;
  *) echo "Aufruf: $0 status|details|profiles|profile|toggle-pct|brightness" >&2; exit 1 ;;
esac
