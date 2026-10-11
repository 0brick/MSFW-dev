#!/usr/bin/env bash
# Hell/Dunkel umschalten (⌘⇧M) – theme.sh toggle|light|dark|menu|apply
# Sway-Variante: wirkt ausschließlich in der Sway-Sitzung.
#  • Wayland-Apps lesen gsettings – die liegen hier in einer eigenen
#    dconf-Datenbank (DCONF_PROFILE aus env-sway.sh). GNOME und Plasma
#    benutzen weiter ihre eigenen Werte.
#  • X-Apps (XWayland) bekommen die Werte über die eigene xsettingsd-Datei.
#  • KDE-Einstellungen (kdeglobals) werden nie verändert.
SETTINGS="$HOME/.config/i3-apple"
MODE_FILE="$SETTINGS/mode"
mode=$(cat "$MODE_FILE" 2>/dev/null || echo dark)

case ${1:-toggle} in
  toggle) [[ $mode == dark ]] && mode=light || mode=dark ;;
  light|dark) mode=$1 ;;
  apply) ;;
  menu)
    choice=$(printf '%s\n' "Dunkel"$'\0icon\x1f'"weather-clear-night" "Hell"$'\0icon\x1f'"weather-clear" |
      python3 "$HOME/.config/sway/scripts/menu.py" -f s -p "Erscheinungsbild" -w 360 -l 2)
    case $choice in Dunkel) mode=dark ;; Hell) mode=light ;; *) exit 0 ;; esac ;;
esac

if [[ $mode == dark ]]; then
  gtk=WhiteSur-Dark;  icons=WhiteSur-dark; scheme=prefer-dark
else
  gtk=WhiteSur-Light; icons=WhiteSur;      scheme=prefer-light
fi
echo "$mode" > "$MODE_FILE"

# X-Apps: eigene xsettingsd-Datei, nur den eigenen xsettingsd neu laden
xs="$SETTINGS/xsettingsd.conf"
if [[ -f $xs ]]; then
  sed -i -e "s|^Net/ThemeName .*|Net/ThemeName \"$gtk\"|" \
         -e "s|^Net/IconThemeName .*|Net/IconThemeName \"$icons\"|" "$xs"
  pkill -HUP -f "xsettingsd -c $xs"
fi

# kitty (nur die Sway-Fassung in ~/.config/sway/kitty): Farben zum
# Erscheinungsbild. Offene Fenster lesen ihre Konfiguration bei SIGUSR1 neu –
# das kann kitty erst ab 0.28; ältere Versionen würden daran beendet.
kitty_dir="$HOME/.config/sway/kitty"
if [[ -f $kitty_dir/colors-$mode.conf ]]; then
  printf '# Von theme.sh geschrieben (Hell/Dunkel) – nicht von Hand ändern\ninclude colors-%s.conf\n' \
    "$mode" > "$kitty_dir/theme.conf"
  if pgrep -u "$UID" -x kitty >/dev/null; then
    kv=$(kitty --version 2>/dev/null | awk '{print $2}')
    if [[ -n $kv && $(printf '%s\n%s\n' 0.28.0 "$kv" | sort -V | head -n1) == 0.28.0 ]]; then
      pkill -USR1 -u "$UID" -x kitty
    fi
  fi
fi

# Wayland-Apps: gsettings – aber nur in der eigenen dconf-Datenbank.
# Ohne sie (z. B. in der normalen „Sway“-Sitzung) bleibt gsettings unangetastet.
if [[ ${DCONF_PROFILE:-} == *i3-apple* ]] && command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.interface gtk-theme "$gtk" 2>/dev/null
  gsettings set org.gnome.desktop.interface icon-theme "$icons" 2>/dev/null
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null
  if [[ ${1:-} == apply ]]; then
    # Startwerte nur setzen, solange nichts eigenes eingetragen ist –
    # selbst geänderte Schrift oder Cursorgröße bleiben erhalten
    default() { # default <schema> <schlüssel> <wert>
      local path="/${1//.//}/$2"
      if command -v dconf >/dev/null; then
        [[ -n $(dconf read "$path" 2>/dev/null) ]] && return 0
      fi
      gsettings set "$1" "$2" "$3" 2>/dev/null
    }
    default org.gnome.desktop.interface cursor-theme 'macOS'
    default org.gnome.desktop.interface cursor-size 24
    default org.gnome.desktop.interface font-name 'SF Pro Text 10'
    default org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
  fi
fi

[[ ${1:-} == apply ]] || notify-send -a "Erscheinungsbild" "$([[ $mode == dark ]] && echo Dunkel || echo Hell)"
