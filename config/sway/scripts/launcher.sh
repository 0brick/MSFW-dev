#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Spotlight-Launcher (rofi-Skriptmodus)
#
#  • Favoriten oben (~/.config/i3-apple/favorites)
#  • alle installierten Apps
#  • Systembefehle (Herunterfahren, Bildschirm sperren, …) – auch englisch suchbar
#  • Dateien & Ordner in ~/Downloads und ~/Documents
#  • kein Treffer + Enter → Websuche in Firefox (Strg+Enter erzwingt sie)
# ═══════════════════════════════════════════════════════════════════
SCRIPTS="$HOME/.config/sway/scripts"
source "$SCRIPTS/desktop-lib.sh"

SETTINGS="$HOME/.config/i3-apple"
FAVORITES="$SETTINGS/favorites"
SEARCH_URL=$(cat "$SETTINGS/search-url" 2>/dev/null || echo 'https://www.google.com/search?q=')

# Direkt aufgerufen → rofi mit diesem Skript als Modus starten
if [[ -z ${ROFI_RETV:-} ]]; then
  exec rofi -show spotlight -modi "spotlight:$0"
fi

detach() { setsid -f "$@" >/dev/null 2>&1 </dev/null; }

entry() { # entry <anzeige> <icon> <info> [suchbegriffe]
  printf '%s\0icon\x1f%s\x1finfo\x1f%s\x1fmeta\x1f%s\n' "$1" "$2" "$3" "${4:-}"
}

# ── Aktionen ────────────────────────────────────────────────────────
system_action() {
  case $1 in
    lock)      detach sh -c "sleep 0.3; exec '$SCRIPTS/lock.sh'" ;;
    poweroff)  detach systemctl poweroff ;;
    reboot)    detach systemctl reboot ;;
    suspend)   detach sh -c 'sleep 0.3; systemctl suspend' ;;
    logout)    detach swaymsg exit ;;
    displays)  detach python3 "$SCRIPTS/displays.py" ;;
    autostart) detach "$SCRIPTS/autostart-manager.sh" ;;
    keys)      detach "$SCRIPTS/keybindings.sh" ;;
    wallpaper) detach "$SCRIPTS/wallpaper.sh" select ;;
    capture)   detach sh -c "sleep 0.3; exec '$SCRIPTS/screenshot.sh' gui" ;;
    theme)     detach "$SCRIPTS/theme.sh" toggle ;;
    settings)  detach "$SCRIPTS/settings-menu.sh" ;;
  esac
}

web_search() {
  local q
  q=$(jq -rn --arg q "$1" '$q | @uri')
  detach "$SCRIPTS/run.sh" browser "$SEARCH_URL$q"
}

case ${ROFI_RETV:-0} in
  1) # Eintrag gewählt
    case $ROFI_INFO in
      app:*)  detach dex "${ROFI_INFO#app:}" ;;
      file:*) detach xdg-open "${ROFI_INFO#file:}" ;;
      sys:*)  system_action "${ROFI_INFO#sys:}" ;;
    esac
    exit 0 ;;
  2) # eigene Eingabe ohne Treffer (oder Strg+Enter) → Websuche
    [[ -n $1 ]] && web_search "$1"
    exit 0 ;;
esac

# ── Liste aufbauen ──────────────────────────────────────────────────
printf '\0prompt\x1f\n'
printf '\0message\x1f%s\n' "Enter öffnet  ·  ohne Treffer oder mit Strg+Enter: im Web suchen"

# Favoriten (pro Zeile mögliche .desktop-IDs, die erste vorhandene zählt)
declare -A fav_ids=()
if [[ -f $FAVORITES ]]; then
  while read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    for id in $line; do
      if path=$(desktop_path "$id"); then
        fav_ids[$id]=1
        IFS=$'\t' read -r name icon file kw < <(desktop_parse "$path")
        [[ -n $name ]] && entry "$name" "$icon" "app:$file" "favorit favorite $kw"
        break
      fi
    done
  done < "$FAVORITES"
fi

# Apps
mapfile -t files < <(desktop_files)
while IFS=$'\t' read -r name icon file kw; do
  [[ -n ${fav_ids[${file##*/}]:-} ]] && continue
  entry "$name" "${icon:-application-x-executable}" "app:$file" "$kw"
done < <(desktop_parse "${files[@]}" | sort -f -t $'\t' -k1,1)

# Systembefehle
entry "Bildschirm sperren"        system-lock-screen  sys:lock      "lock screen sperren"
entry "Herunterfahren"            system-shutdown     sys:poweroff  "shutdown power off ausschalten"
entry "Neu starten"               system-reboot       sys:reboot    "restart reboot neustart"
entry "Ruhezustand"               system-suspend      sys:suspend   "suspend sleep standby"
entry "Abmelden"                  system-log-out      sys:logout    "logout log out exit"
entry "Bildschirme anordnen"      video-display       sys:displays  "display monitor screens arrange anordnung skalierung scale"
entry "Autostart-Apps verwalten"  system-run          sys:autostart "autostart startup apps"
entry "Tastenkürzel anzeigen"     preferences-desktop-keyboard-shortcuts sys:keys "keybindings shortcuts keys"
entry "Hintergrundbild wählen"    preferences-desktop-wallpaper sys:wallpaper "wallpaper background"
entry "Bildschirmfoto & Aufnahme" media-record        sys:capture   "screenshot screen recording video aufnahme bildschirmfoto"
entry "Hell / Dunkel umschalten"  preferences-desktop-theme sys:theme "dark light mode theme"
entry "Einstellungen"             preferences-system  sys:settings  "settings preferences config"

# Dateien & Ordner (setzt $ICON statt auszugeben – spart tausende Subshells)
file_icon() {
  case ${1,,} in
    *.pdf)                                   ICON=application-pdf ;;
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.heic|*.bmp) ICON=image-x-generic ;;
    *.mp3|*.flac|*.wav|*.ogg|*.m4a|*.opus)    ICON=audio-x-generic ;;
    *.mp4|*.mkv|*.webm|*.mov|*.avi)           ICON=video-x-generic ;;
    *.zip|*.tar|*.gz|*.xz|*.bz2|*.7z|*.rar|*.zst) ICON=package-x-generic ;;
    *.doc|*.docx|*.odt|*.rtf)                 ICON=x-office-document ;;
    *.xls|*.xlsx|*.ods|*.csv)                 ICON=x-office-spreadsheet ;;
    *.ppt|*.pptx|*.odp|*.key)                 ICON=x-office-presentation ;;
    *.sh|*.py|*.js|*.ts|*.rs|*.go|*.c|*.cpp|*.java|*.rb|*.php|*.json|*.yaml|*.yml|*.toml) ICON=text-x-script ;;
    *.html|*.htm)                             ICON=text-html ;;
    *.deb)                                    ICON=application-x-deb ;;
    *.iso|*.img)                              ICON=media-optical ;;
    *)                                        ICON=text-x-generic ;;
  esac
}

dirs=()
declare -A seen_dir=()
for d in "$HOME/Downloads" "$HOME/Documents" \
         "$(xdg-user-dir DOWNLOAD 2>/dev/null)" "$(xdg-user-dir DOCUMENTS 2>/dev/null)"; do
  [[ -d $d && $d != "$HOME" ]] || continue
  real=$(realpath "$d")
  [[ -n ${seen_dir[$real]:-} ]] && continue
  seen_dir[$real]=1
  dirs+=("$real")
done

if (( ${#dirs[@]} )); then
  while IFS=$'\t' read -r type path; do
    name=${path##*/}
    dir=${path%/*}
    dir=${dir/#$HOME/\~}
    if [[ $type == d ]]; then ICON=folder; else file_icon "$name"; fi
    entry "$name   ·   $dir" "$ICON" "file:$path" "datei file"
  done < <(find "${dirs[@]}" -mindepth 1 -maxdepth 4 -not -path '*/.*' -printf '%y\t%p\n' 2>/dev/null | head -n 4000)
fi
