#!/usr/bin/env bash
# Touchpad und Tastatur einrichten (bei jedem Start/Neuladen von Sway).
# Unter Plasma übernimmt das KDE selbst – in Sway fehlt es sonst:
# kein Antippen zum Klicken, falsche Scrollrichtung, US-Layout.
# Einstellungen: ~/.config/i3-apple/input
CONF="$HOME/.config/i3-apple/input"

tap=1 natural_scroll=1 disable_while_typing=1 mouse_natural_scroll=0
repeat_delay=300 repeat_rate=30 layout="" variant="" options=""
if [[ -f $CONF ]]; then
  while IFS='=' read -r key value; do
    # Kommentar am Zeilenende und Leerraum entfernen – sonst würde „tap=1 # an“
    # als ungültig verworfen
    value=${value%%#*}
    value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
    value=${value%\"}; value=${value#\"}
    case $key in
      tap|natural_scroll|disable_while_typing|mouse_natural_scroll|repeat_delay|repeat_rate)
        [[ $value =~ ^[0-9]+$ ]] && printf -v "$key" '%s' "$value" ;;
      layout|variant|options)
        [[ $value =~ ^[A-Za-z0-9_,:()+-]*$ ]] && printf -v "$key" '%s' "$value" ;;
    esac
  done < <(grep -E '^[a-z_]+=' "$CONF")
fi

# Wert aus ~/.config/kxkbrc (KDE-Tastatureinstellungen), Gruppe [Layout]
kxkb() {
  awk -F= -v k="$1" '/^\[/ { s = ($0 == "[Layout]") } s && $1 == k { print substr($0, length(k) + 2); exit }' \
    "$HOME/.config/kxkbrc" 2>/dev/null
}

# Wert aus /etc/default/keyboard (Systemstandard unter Debian/Ubuntu) –
# den liest Sway anders als der X-Server nicht von selbst
syskb() {
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" /etc/default/keyboard 2>/dev/null | head -n1
}

# ── Tastatur ────────────────────────────────────────────────────────
if [[ -z $layout && $(kxkb Use) == true ]]; then
  layout=$(kxkb LayoutList) variant=$(kxkb VariantList) options=$(kxkb Options)
fi
if [[ -z $layout ]]; then
  layout=$(syskb XKBLAYOUT) variant=$(syskb XKBVARIANT) options=$(syskb XKBOPTIONS)
fi
safe='^[A-Za-z0-9_,:()+-]*$'
[[ $layout =~ $safe && $variant =~ $safe && $options =~ $safe ]] || layout=""

kb=()
if [[ -n $layout ]]; then
  kb+=("input type:keyboard xkb_layout $layout")
  kb+=("input type:keyboard xkb_variant \"${variant}\"")
  kb+=("input type:keyboard xkb_options \"${options}\"")
fi
kb+=("input type:keyboard repeat_delay $repeat_delay")
kb+=("input type:keyboard repeat_rate $repeat_rate")

# ── Touchpad & Maus (libinput) ──────────────────────────────────────
onoff() { if (( $1 )); then echo enabled; else echo disabled; fi; }
kb+=("input type:touchpad tap $(onoff "$tap")")
kb+=("input type:touchpad natural_scroll $(onoff "$natural_scroll")")
kb+=("input type:touchpad dwt $(onoff "$disable_while_typing")")
kb+=("input type:pointer natural_scroll $(onoff "$mouse_natural_scroll")")

# Was in ~/.config/i3-apple/sway-user.conf selbst eingestellt ist, hat Vorrang –
# input.sh läuft nach der Konfiguration und würde es sonst überschreiben.
# Verglichen wird je Gerätetyp: ein touchpad-natural_scroll dort unterdrückt
# nicht das der Maus. Kennungen einzelner Geräte und „*“ zählen für alle Typen.
# Erkennt einzeilige Befehle und Blöcke (input type:touchpad { … }).
USER_CONF="$HOME/.config/i3-apple/sway-user.conf"
user_sets() { # user_sets <typ> <schlüssel>
  [[ -f $USER_CONF ]] || return 1
  awk -v t="type:$1" -v k="$2" '
    function hit(id) { return id == t || id == "*" || id !~ /^type:/ }
    { sub(/#.*/, ""); gsub(/"/, "") }
    blk != "" && /\}/ { blk = ""; next }
    blk != "" { if (hit(blk) && $1 == k) found = 1; next }
    $1 == "input" {
      if ($NF == "{") { blk = $2; next }
      if (hit($2) && $3 == k) found = 1
    }
    END { exit !found }' "$USER_CONF"
}

for c in "${kb[@]}"; do
  read -r _ type key _ <<<"$c"                    # z. B. type:touchpad natural_scroll
  type=${type#type:}
  [[ $key == xkb_* ]] && user_sets "$type" xkb_layout && continue
  user_sets "$type" "$key" && continue
  swaymsg -q -- "$c" 2>/dev/null
done
exit 0
