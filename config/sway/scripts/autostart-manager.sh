#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Autostart-Apps verwalten (nur für die Sway-Sitzung)
#  Grundlage ist der XDG-Standard (~/.config/autostart, /etc/xdg/autostart),
#  aber andere Desktops bleiben unberührt:
#   • Ausschalten verändert keine .desktop-Datei, sondern trägt die App in
#     ~/.config/i3-apple/autostart-disabled-sway ein.
#   • Hinzugefügte Apps bekommen eine eigene Datei i3apple-sway-*.desktop mit
#     OnlyShowIn=sway – Plasma, GNOME & Co. ignorieren sie.
#  Gestartet werden die Einträge von autostart.sh (autostart_run).
# ═══════════════════════════════════════════════════════════════════
source "$HOME/.config/sway/scripts/desktop-lib.sh"

USER_DIR="$HOME/.config/autostart"
SYS_DIR=/etc/xdg/autostart
DISABLED="$HOME/.config/i3-apple/autostart-disabled-sway"
mkdir -p "$USER_DIR" "${DISABLED%/*}"
touch "$DISABLED"

# Startet der Eintrag in Sway überhaupt? (KDE-eigene Dienste haben OnlyShowIn=KDE)
for_sway() {
  ! grep -q '^OnlyShowIn=' "$1" || grep -qE '^OnlyShowIn=(.*;)?sway(;|$)' "$1"
}

# Überall ausgeschaltet (Hidden=true usw.) – das ändern nur die Systemeinstellungen
globally_off() {
  grep -qE '^(Hidden=true|X-GNOME-Autostart-enabled=false)' "$1" ||
    grep -qE '^NotShowIn=(.*;)?sway(;|$)' "$1"
}

enabled() { # enabled <id> <datei>
  ! globally_off "$2" && ! grep -qxF -- "$1" "$DISABLED"
}

toggle() { # toggle <id> <datei>
  if [[ $1 == i3apple-sway-* ]]; then        # eigener Eintrag → einfach entfernen
    rm -f "$USER_DIR/$1"
    notify-send -a "Autostart" "Autostart entfernt"
  elif globally_off "$2"; then
    notify-send -a "Autostart" "In allen Desktops ausgeschaltet" \
      "Diese App ist systemweit oder in den Plasma-/GNOME-Einstellungen ausgeschaltet."
  elif grep -qxF -- "$1" "$DISABLED"; then
    grep -vxF -- "$1" "$DISABLED" > "$DISABLED.tmp"; mv "$DISABLED.tmp" "$DISABLED"
  else
    echo "$1" >> "$DISABLED"
  fi
}

add_app() {
  local files choice name icon file target
  mapfile -t files < <(desktop_files)
  local -a lines=() paths=()
  while IFS=$'\t' read -r name icon file _; do
    lines+=("$name"$'\0icon\x1f'"$icon")
    paths+=("$file")
  done < <(desktop_parse "${files[@]}" | sort -f -t $'\t' -k1,1)

  choice=$(printf '%s\n' "${lines[@]}" |
    python3 "$HOME/.config/sway/scripts/menu.py" -p "App für den Autostart suchen" -w 560 -l 10)
  [[ $choice =~ ^[0-9]+$ ]] || return
  file=${paths[$choice]}
  target="$USER_DIR/i3apple-sway-${file##*/}"
  cp "$file" "$target"
  # nur in Sway starten – der Autostart anderer Desktops bleibt unverändert
  sed -i -e '/^Hidden=/d; /^X-GNOME-Autostart-enabled=/d; /^OnlyShowIn=/d; /^NotShowIn=/d' \
         -e '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nOnlyShowIn=sway;/' "$target"
  notify-send -a "Autostart" "Autostart aktiviert" "$(sed -n 's/^Name=//p' "$file" | head -n1)"
}

while true; do
  # Alle Einträge sammeln (Benutzer-Dateien überschreiben System-Dateien)
  declare -A path_of=()
  for f in "$SYS_DIR"/*.desktop "$USER_DIR"/*.desktop; do
    [[ -f $f ]] && path_of[${f##*/}]=$f
  done
  for id in "${!path_of[@]}"; do
    for_sway "${path_of[$id]}" || unset "path_of[$id]"
  done

  rows=("App hinzufügen …"$'\0icon\x1f'"list-add")
  ids=("") files=("")
  active=()
  i=1
  while IFS=$'\t' read -r name icon file _; do
    id=${file##*/}
    if enabled "$id" "$file"; then state="an"; active+=("$i"); else state="aus"; fi
    rows+=("$name"$'\t'"$state"$'\0icon\x1f'"$icon")   # zwei Spalten: App | an/aus
    ids+=("$id"); files+=("$file")
    i=$((i + 1))
  done < <(desktop_parse --all "${path_of[@]}" | sort -f -t $'\t' -k1,1)

  active_arg=$(IFS=,; echo "${active[*]}")
  choice=$(printf '%s\n' "${rows[@]}" |
    python3 "$HOME/.config/sway/scripts/menu.py" -p "Autostart-Apps" -w 520 -l 10 \
      ${active_arg:+-a "$active_arg"} \
      -m "Enter oder Klick schaltet eine App an oder aus  ·  gilt nur für Sway  ·  Esc schließt")

  [[ $choice =~ ^[0-9]+$ ]] || exit 0
  if (( choice == 0 )); then add_app; else toggle "${ids[$choice]}" "${files[$choice]}"; fi
  unset path_of
done
