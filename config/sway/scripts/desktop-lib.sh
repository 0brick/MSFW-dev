#!/usr/bin/env bash
# Gemeinsame Helfer: installierte Apps (.desktop-Dateien) auslesen.
# Wird per `source` geladen (launcher.sh, autostart-manager.sh, windows.sh).

# Benutzer zuerst, dann $XDG_DATA_DIRS (enthält z. B. Snap- oder Nix-Ordner),
# dann die üblichen Systemordner – jeder Ordner nur einmal
APP_DIRS=()
_app_dirs() {
  local d e
  local -a xdg
  IFS=: read -ra xdg <<<"${XDG_DATA_DIRS:-}"
  for d in "${XDG_DATA_HOME:-$HOME/.local/share}" "$HOME/.local/share/flatpak/exports/share" \
           "${xdg[@]}" /var/lib/flatpak/exports/share /usr/local/share /usr/share; do
    [[ -n $d ]] || continue
    d="${d%/}/applications"
    for e in "${APP_DIRS[@]}"; do [[ $e == "$d" ]] && continue 2; done
    APP_DIRS+=("$d")
  done
}
_app_dirs

# Pfad zur .desktop-Datei mit dieser ID (Benutzer-Dateien haben Vorrang)
desktop_path() {
  local d
  for d in "${APP_DIRS[@]}"; do
    [[ -f $d/$1 ]] && { echo "$d/$1"; return 0; }
  done
  return 1
}

# Alle sichtbaren .desktop-Dateien, je ID nur einmal
desktop_files() {
  local d f id
  declare -A seen=()
  for d in "${APP_DIRS[@]}"; do
    for f in "$d"/*.desktop; do
      [[ -f $f ]] || continue
      id=${f##*/}
      [[ -n ${seen[$id]:-} ]] && continue
      seen[$id]=1
      printf '%s\n' "$f"
    done
  done
}

# Liest .desktop-Dateien (Pfade als Argumente) und gibt pro App aus:
#   Name<TAB>Icon<TAB>Pfad<TAB>Suchbegriffe
# Versteckte Einträge und Einträge nur für andere Desktops werden ausgelassen
# (mit --all werden auch diese ausgegeben, z. B. für Autostart-Einträge).
desktop_parse() {
  local all=0
  [[ ${1:-} == --all ]] && { all=1; shift; }
  (( $# )) || return 0
  local lang=${LANG%%.*}
  awk -v lang="$lang" -v short="${lang%%_*}" -v all="$all" '
    function flush() {
      if (file != "" && (app || all) && (all || !hide)) {
        n = (lname != "") ? lname : (sname != "" ? sname : name)
        # Felder nie leer lassen: read mit IFS=Tab würde leere Felder zusammenfassen
        if (icon == "") icon = "application-x-executable"
        if (n != "") print n "\t" icon "\t" file "\t" kw " " gname " " exe " ."
      }
    }
    FNR == 1 { flush(); file = FILENAME; insec = 0; name = ""; lname = ""; sname = ""; icon = ""
               hide = 0; app = 0; kw = ""; gname = ""; exe = "" }
    /^\[/ { insec = ($0 == "[Desktop Entry]"); next }
    !insec { next }
    /^Name=/ { name = substr($0, 6); next }
    index($0, "Name[" lang "]=") == 1  { lname = substr($0, length(lang) + 8); next }
    index($0, "Name[" short "]=") == 1 { sname = substr($0, length(short) + 8); next }
    /^GenericName=/ { gname = substr($0, 13); next }
    /^Keywords=/ { kw = substr($0, 10); gsub(/;/, " ", kw); next }
    /^Exec=/ { exe = substr($0, 6); sub(/ .*/, "", exe); sub(/.*\//, "", exe); next }
    /^Icon=/ { icon = substr($0, 6); next }
    /^Type=Application/ { app = 1; next }
    /^(NoDisplay|Hidden)=true/ { hide = 1; next }
    # Desktop-Namen als ganze Einträge der Liste vergleichen (wie autostart.sh)
    /^OnlyShowIn=/ { if ($0 !~ /[=;]sway(;|$)/) hide = 1; next }
    /^NotShowIn=/  { if ($0 ~ /[=;]sway(;|$)/) hide = 1; next }
    END { flush() }
  ' "$@"
}
