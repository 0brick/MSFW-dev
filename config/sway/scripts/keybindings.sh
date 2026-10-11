#!/usr/bin/env bash
# Zeigt alle Tastenkürzel (⌘⌃K). Beschreibungen stammen aus „#: …“-Zeilen
# direkt über dem jeweiligen bindsym in der Sway-Konfiguration.
# Zwei echte Spalten (Taste<TAB>Beschreibung) im Menüfenster menu.py – alle
# Beschreibungen beginnen an derselben Stelle, unabhängig von der Schrift.
CONFIG="$HOME/.config/sway/config"
USER_CONF="$HOME/.config/i3-apple/sway-user.conf"   # eigene Kürzel (zuletzt geladen)
files=("$CONFIG")
[[ -f $USER_CONF ]] && files+=("$USER_CONF")

mapfile -t rows < <(awk '
  function pretty(k,   n, p, i, s, out) {
    n = split(k, p, "+")
    for (i = 1; i <= n; i++) {
      s = p[i]
      if (s == "$mod" || s == "Mod4")          s = "Super"
      else if (s == "$alt" || s == "Mod1")     s = "Alt"
      else if (s == "Control" || s == "Ctrl")  s = "Strg"
      else if (s == "Return")                  s = "Enter"
      else if (s == "space")                   s = "Leertaste"
      else if (s == "Left")                    s = "Links"
      else if (s == "Right")                   s = "Rechts"
      else if (s == "Up")                      s = "Oben"
      else if (s == "Down")                    s = "Unten"
      else if (s == "Print")                   s = "Druck"
      else if (s == "button4")                 s = "Mausrad hoch"
      else if (s == "button5")                 s = "Mausrad runter"
      else if (s == "XF86AudioRaiseVolume")    s = "Taste Lauter"
      else if (s == "XF86AudioLowerVolume")    s = "Taste Leiser"
      else if (s == "XF86AudioMute")           s = "Taste Stumm"
      else if (s == "XF86AudioMicMute")        s = "Taste Mikrofon"
      else if (s == "XF86MonBrightnessUp")     s = "Taste Heller"
      else if (s == "XF86MonBrightnessDown")   s = "Taste Dunkler"
      else if (s == "XF86AudioPlay")           s = "Taste Play"
      else if (s == "XF86AudioPause")          s = "Taste Pause"
      else if (s == "XF86AudioNext")           s = "Taste Weiter"
      else if (s == "XF86AudioPrev")           s = "Taste Zurück"
      else if (s ~ /^XF86/)                    { s = "Taste " substr(s, 5) }
      else if (length(s) == 1)                 s = toupper(s)
      out = (i == 1) ? s : out " + " s
    }
    return out
  }
  FNR == 1 { desc = "" }   # Beschreibung nie über das Dateiende hinaus mitnehmen
  /^[[:space:]]*#: / { desc = $0; sub(/^[[:space:]]*#: /, "", desc); next }
  /^[[:space:]]*bindsym / {
    line = $0; sub(/^[[:space:]]*bindsym[[:space:]]+(--[a-z-]+[[:space:]]+)*/, "", line)
    key = line; sub(/[[:space:]].*/, "", key)
    if (desc != "") print pretty(key) "\t" desc
    desc = ""; next
  }
  { desc = "" }
' "${files[@]}")

(( ${#rows[@]} )) || exit 0

printf '%s\n' "${rows[@]}" |
  python3 "$HOME/.config/sway/scripts/menu.py" -p "Tastenkürzel durchsuchen" -w 760 -l 14 >/dev/null
