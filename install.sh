#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  i3-apple · Sway-Variante (Wayland) · Installer
#  (KDE neon, Kubuntu/Ubuntu, Debian)
#
#  sway/install.sh                 alles installieren
#  sway/install.sh --no-packages   keine apt-Pakete installieren
#  sway/install.sh --no-themes     WhiteSur-Themes & macOS-Cursor überspringen
#  sway/install.sh --no-eww        eww nicht bauen
#  sway/install.sh --no-rofi       rofi nicht mit Wayland bauen (läuft dann über XWayland)
#  sway/install.sh --config-only   nur Konfiguration kopieren (schnell, für Änderungen)
#
#  SwayFX (Unschärfe, Schatten, runde Ecken) ist Pflicht: Fehlt es, wird es bei
#  jedem Lauf gebaut – auch mit --config-only. Klappt das nicht, bricht der
#  Installer ab (Protokoll: ~/.cache/i3-apple/swayfx-build.log).
#
#  Sicherung: Vor jeder Änderung landen alle betroffenen Dateien als .tar.gz
#  in ~/i3-apple-Backups (änderbar mit --backup-dir=PFAD).
#  sway/install.sh --backup-only        nur sichern, nichts verändern
#  sway/install.sh --no-backup          ohne Sicherung installieren
#  sway/install.sh --restore [ARCHIV]   Sicherung zurückspielen (ohne ARCHIV: die neueste)
#
#  Grundsatz: GNOME, KDE Plasma und andere Desktops bleiben unberührt.
#  • Alles Sichtbare liegt in eigenen Ordnern (~/.config/sway, ~/.config/i3-apple);
#    ~/.config/rofi, dunst, kitty, gtk-3.0/4.0, kdeglobals, der Standard-Cursor
#    und die normalen gsettings werden nicht angefasst.
#  • GTK-Einstellungen der Sway-Sitzung landen in einer eigenen dconf-Datenbank.
#  • Pakete werden nie entfernt (Simulation + apt-get --no-remove).
#  Einzige Ausnahme: ein vorhandenes ~/.local/bin/eww ohne Wayland wird durch
#  eine Version für X11 *und* Wayland ersetzt.
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

SWAY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE="$HOME/.cache/i3-apple"
TS=$(date +%Y%m%d-%H%M%S)
EWW_VERSION="v0.6.0"
ROFI_VERSION="2.0.0"
ROFI_PREFIX="$HOME/.local/share/i3-apple/rofi-wayland"
# Selbst gebautes SwayFX: Verweis auf den Ordner der gebauten Version (swayfx-<tag>)
SWAYFX_PREFIX="$HOME/.local/share/i3-apple/swayfx"
SWAYFX_URL="https://github.com/wlrfx/swayfx"   # früher WillPower3309/swayfx (leitet weiter)
SCENEFX_URL="https://github.com/wlrfx/scenefx"
WLROOTS_URL="https://gitlab.freedesktop.org/wlroots/wlroots.git"
BACKUP_DIR="$HOME/i3-apple-Backups"
BACKUP_PREFIX="sway-apple-backup"

msg()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }

# ALLOW_APT: Build-Pakete für SwayFX dürfen auch mit --config-only nachinstalliert
# werden (SwayFX ist Pflicht) – nur --no-packages verbietet apt ganz.
DO_PACKAGES=1 DO_THEMES=1 DO_EWW=1 DO_ROFI=1 ALLOW_APT=1
DO_BACKUP=1 BACKUP_ONLY=0 RESTORE=""
while (( $# )); do
  case $1 in
    --no-packages)  DO_PACKAGES=0; ALLOW_APT=0 ;;
    --no-themes)    DO_THEMES=0 ;;
    --no-eww)       DO_EWW=0 ;;
    --no-rofi)      DO_ROFI=0 ;;
    --config-only)  DO_PACKAGES=0; DO_THEMES=0; DO_EWW=0; DO_ROFI=0 ;;
    --no-backup)    DO_BACKUP=0 ;;
    --backup-only)  BACKUP_ONLY=1 ;;
    --backup-dir=*) BACKUP_DIR=${1#*=} ;;
    --restore=*)    RESTORE=${1#*=} ;;
    --restore)
      RESTORE=latest
      if [[ -n ${2:-} && $2 != --* ]]; then RESTORE=$2; shift; fi ;;
    -h|--help)      sed -n '3,/^# ═/{/^# ═/!p}' "$0"; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 1 ;;
  esac
  shift
done
[[ -n $BACKUP_DIR ]] || { echo "--backup-dir braucht einen Pfad" >&2; exit 1; }

if [[ $EUID -eq 0 ]]; then
  echo "Bitte als normaler Benutzer ausführen (sudo wird bei Bedarf abgefragt)." >&2
  exit 1
fi

mkdir -p "$CACHE" "$HOME/.local/bin" "$CFG"

# ── System erkennen ─────────────────────────────────────────────────
OS_ID=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
OS_LIKE=$(. /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}")
OS_NAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unbekannt}")

# KDE: Plasma ist installiert (KDE neon, Kubuntu …) – dann KDE-Apps statt GTK-Werkzeuge
KDE=0
if [[ $OS_ID == neon ]] || command -v plasmashell >/dev/null; then KDE=1; fi

# Ubuntu-Familie: firefox/thunderbird aus apt sind dort nur Snap-Platzhalter
UBUNTU=0
if [[ $OS_ID == ubuntu || $OS_ID == neon || $OS_LIKE == *ubuntu* ]]; then UBUNTU=1; fi

# Intel-Grafik (Hersteller-ID 0x8086)
INTEL=0
if grep -qi '0x8086' /sys/class/drm/card*/device/vendor 2>/dev/null; then INTEL=1; fi

msg "System: $OS_NAME"
(( KDE ))   && ok "KDE Plasma erkannt – Dolphin, KCalc & KDE-Einstellungsmodule werden genutzt"
(( INTEL )) && ok "Intel-Grafik erkannt – Vulkan- und Videobeschleunigung werden eingerichtet"

# ── Pakete ──────────────────────────────────────────────────────────
# Nur Pakete, die in anderen Desktops nichts selbst starten: keine Tray-Applets
# mit eigenem Autostart (z. B. blueman), kein zweiter Mitteilungsdienst aktiv
# (dunst wird unten auf die Sway-Sitzung beschränkt).
PACKAGES=(
  # Compositor & Sitzung (Wayland); sway wird durch swayfx ersetzt, wenn verfügbar –
  # sonst baut build_swayfx SwayFX selbst in einen eigenen Ordner
  sway swaybg swayidle swaylock xwayland kanshi wl-clipboard wtype
  xdg-desktop-portal-wlr xdg-desktop-portal-gtk dex xdg-user-dirs qtwayland5 qt6-wayland
  # Oberfläche
  rofi dunst libnotify-bin kitty imagemagick xsettingsd dconf-cli
  # Daten für die Menüleiste
  jq network-manager bluez rfkill pulseaudio-utils
  power-profiles-daemon upower brightnessctl playerctl
  # Werkzeuge (ML4W-Tastenkürzel): Screenshots, Spiegeln, Blaulicht, Emoji, OCR
  grim slurp swappy wf-recorder wl-mirror gammastep rofimoji tesseract-ocr tesseract-ocr-deu tesseract-ocr-eng
  # Fenster für Hintergrundbild-Auswahl und Bildschirm-Einstellungen
  python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0
  # Grafik: Vulkan (Zed, kitty) – bei Intel der ANV-Treiber
  mesa-vulkan-drivers
  # Schriften & Theming (SF Pro ist bereits installiert)
  fonts-jetbrains-mono librsvg2-common
  git curl xz-utils sassc libglib2.0-dev-bin libxml2-utils
  # eww bauen (X11 + Wayland/Layer-Shell)
  build-essential pkg-config cargo
  libgtk-3-dev libgtk-layer-shell-dev libpango1.0-dev libgdk-pixbuf-2.0-dev libcairo2-dev
  libglib2.0-dev libdbusmenu-gtk3-dev
  # rofi mit Wayland bauen (nur genutzt, wenn das rofi der Distribution es nicht kann)
  meson ninja-build flex bison libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev
)
if (( KDE )); then
  # Meist schon vorhanden; kde-cli-tools bringt kcmshell6, kinfocenter die Akku-Ansicht
  PACKAGES+=(polkit-kde-agent-1 dolphin kcalc kde-cli-tools kinfocenter
             plasma-nm plasma-pa bluedevil plasma-integration)
else
  # polkit-gnome/nm-applet starten in GNOME selbst nicht (eigene Autostart-Bedingungen)
  PACKAGES+=(policykit-1-gnome polkit-gnome network-manager-gnome pavucontrol
             gnome-power-manager gnome-calculator nautilus
             qt5-gtk-platformtheme qt6-gtk-platformtheme adwaita-icon-theme)
fi
(( UBUNTU )) || PACKAGES+=(firefox-esr thunderbird)
(( INTEL ))  && PACKAGES+=(intel-media-va-driver vainfo)

# ── Paket-Sicherheitsregeln ─────────────────────────────────────────
#  1. Nur auf einem intakten System installieren (dpkg --audit, apt-get check).
#  2. Nichts verlangen, was schon installiert ist oder bereitgestellt wird.
#  3. Jedes Paket vorher simulieren: würde apt etwas entfernen oder findet es
#     keine Lösung, wird das Paket ausgelassen.
#  4. Die echte Installation läuft mit --no-remove: apt bricht ab, statt zu
#     entfernen – selbst wenn die Simulation etwas übersehen hätte.
#  5. Vorhandene Systemkonfigurationen bleiben (dpkg --force-confold).
#  6. Keine empfohlenen Zusatzpakete (die ziehen sonst fremde Desktop-Teile nach).
#  7. Paketliste vorher und installierte Pakete landen im Sicherungsordner.
APT_OPTS=(-y --no-remove --no-install-recommends
          -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

apt_healthy() {
  [[ -z $(dpkg --audit 2>/dev/null) ]] && sudo apt-get check >/dev/null 2>&1
}

apt_broken_hint() {
  echo >&2
  echo "Die Paketverwaltung hat bereits unerfüllte Abhängigkeiten – der Installer" >&2
  echo "installiert nichts, bis das behoben ist:" >&2
  sudo apt-get check 2>&1 | sed 's/^/    /' >&2 || true
  echo >&2
  if [[ $OS_ID == neon ]] && ! dpkg -s neon-adwaita >/dev/null 2>&1; then
    echo "KDE neon: Das Paket neon-adwaita fehlt. Reparatur:" >&2
    echo "    sudo apt install neon-adwaita" >&2
  else
    echo "Reparatur:  sudo dpkg --configure -a && sudo apt --fix-broken install" >&2
    echo "(Vor dem Bestätigen lesen, was apt entfernen möchte.)" >&2
  fi
  echo "Danach sway/install.sh erneut starten." >&2
}

# 0, wenn apt die Pakete ohne Entfernen installieren kann (nur Simulation, ohne root)
apt_sim_ok() {
  local out
  out=$(LC_ALL=C apt-get install -s "${APT_OPTS[@]}" "$@" 2>&1) || return 1
  ! grep -q '^Remv ' <<<"$out"
}

pkg_installed() { dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'; }
pkg_available() { apt-cache show "$1" >/dev/null 2>&1; }

replace_pkg() { # replace_pkg <alt> <neu>
  local i
  for i in "${!PACKAGES[@]}"; do [[ ${PACKAGES[$i]} == "$1" ]] && PACKAGES[$i]=$2; done
}

install_packages() {
  command -v apt-get >/dev/null || { warn "Kein apt gefunden – Pakete bitte manuell installieren (siehe sway/README.md)."; return; }
  msg "Systempakete installieren"
  if ! command -v sudo >/dev/null; then
    warn "sudo ist nicht installiert – Pakete werden übersprungen."
    warn "Als root nachholen: su -c 'apt install sudo && adduser $USER sudo' (danach neu anmelden)"
    return 0
  fi
  if ! apt_healthy; then apt_broken_hint; exit 1; fi
  sudo apt-get update

  # SwayFX (Sway mit runden Ecken, Schatten und Unschärfe) statt Sway – aber nur,
  # wenn Sway noch nicht installiert ist und dabei nichts entfernt würde
  if ! pkg_installed sway && pkg_available swayfx && apt_sim_ok swayfx; then
    replace_pkg sway swayfx
    ok "SwayFX-Paket verfügbar – Unschärfe, Schatten und runde Ecken"
  fi
  # Zwischenablage-Verlauf: cliphist (Text und Bilder), sonst clipman
  if pkg_available cliphist; then PACKAGES+=(cliphist); else PACKAGES+=(clipman); fi

  # power-profiles-daemon verdrängt TLP – nicht ungefragt ersetzen
  if dpkg -s tlp >/dev/null 2>&1; then
    warn "TLP ist installiert – power-profiles-daemon wird ausgelassen (Energiemodus im Batterie-Popup bleibt leer)."
    PACKAGES=("${PACKAGES[@]/power-profiles-daemon}")
  fi

  # Was installierte Pakete bereits „bereitstellen“ (Provides). KDE neon ersetzt z. B.
  # adwaita-icon-theme durch neon-adwaita – das Ubuntu-Paket zu verlangen,
  # würde neon-adwaita entfernen und GTK, ibus & Co. die Abhängigkeit nehmen.
  local provided
  provided=$(dpkg-query -W -f='${db:Status-Abbrev}|${Provides}\n' 2>/dev/null |
             awk -F'|' '$1 ~ /^ii/ { print $2 }' | tr ',' '\n' |
             sed 's/([^)]*)//g; s/:any//; s/^ *//; s/ *$//' | sort -u)

  local available=() p
  for p in "${PACKAGES[@]}"; do
    [[ -z $p ]] && continue
    if pkg_installed "$p"; then
      continue                                   # schon installiert
    elif grep -qxF -- "$p" <<<"$provided"; then
      ok "Wird schon von einem anderen Paket bereitgestellt: $p"
    elif pkg_available "$p"; then
      available+=("$p")
    else
      warn "Paket nicht verfügbar, übersprungen: $p"
    fi
  done
  if (( ${#available[@]} == 0 )); then ok "Alle Pakete sind bereits installiert"; return; fi

  # Jedes Paket einzeln simulieren und nur unbedenkliche behalten
  local keep=()
  for p in "${available[@]}"; do
    if apt_sim_ok "$p"; then
      keep+=("$p")
    else
      warn "Übersprungen – würde andere Pakete entfernen oder ist nicht installierbar: $p"
    fi
  done
  available=("${keep[@]}")
  (( ${#available[@]} )) || return 0
  # … und alle zusammen (Konflikte untereinander)
  if ! apt_sim_ok "${available[@]}"; then
    warn "Die Pakete vertragen sich zusammen nicht – Paketinstallation ausgelassen."
    warn "Von Hand prüfen: apt-get install -s ${available[*]}"
    return 0
  fi

  # Protokoll: Paketliste vorher und was der Installer hinzufügt
  mkdir -p "$BACKUP_DIR"
  dpkg --get-selections > "$BACKUP_DIR/paketliste-vorher-$TS.txt"
  {
    echo "# Von i3-apple (Sway) am $(date '+%d.%m.%Y %H:%M') installierte Pakete"
    echo "# Zum Entfernen (vorher mit -s simulieren!): sudo apt-get remove \$(grep -v '^#' DATEI)"
    printf '%s\n' "${available[@]}"
  } > "$BACKUP_DIR/sway-apple-pakete-$TS.txt"

  sudo apt-get install "${APT_OPTS[@]}" "${available[@]}"

  if apt_healthy; then
    ok "Pakete installiert (Liste: $BACKUP_DIR/sway-apple-pakete-$TS.txt)"
  else
    apt_broken_hint
    exit 1
  fi

  # Helligkeit ohne Passwort ändern (brightnessctl → Gruppe video)
  if ! id -nG "$USER" | grep -qw video; then
    sudo usermod -aG video "$USER" && ok "Benutzer zur Gruppe „video“ hinzugefügt (Helligkeit, wirkt nach Neuanmeldung)"
  fi
}

# ── Firefox & Thunderbird (Favoriten) ───────────────────────────────
# Unter Ubuntu/KDE neon sind die apt-Pakete nur Snap-Platzhalter –
# fehlt eine App, kommt sie deshalb als Flatpak von Flathub (nur für deinen Benutzer).
has_flatpak() { command -v flatpak >/dev/null && flatpak info "$1" >/dev/null 2>&1; }

install_apps() {
  local missing=()
  command -v firefox >/dev/null || command -v firefox-esr >/dev/null ||
    has_flatpak org.mozilla.firefox || missing+=(org.mozilla.firefox)
  command -v thunderbird >/dev/null || has_flatpak net.thunderbird.Thunderbird ||
    has_flatpak org.mozilla.Thunderbird || missing+=(net.thunderbird.Thunderbird)
  if (( ${#missing[@]} == 0 )); then ok "Firefox und Thunderbird sind vorhanden"; return; fi

  if ! command -v flatpak >/dev/null; then
    warn "Fehlt noch: ${missing[*]} – bitte über Discover/Software installieren"
    return
  fi
  msg "Fehlende Apps als Flatpak installieren: ${missing[*]}"
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub "${missing[@]}" || warn "Flatpak-Installation fehlgeschlagen – bitte über Discover/Software installieren"
}

install_zed() {
  if command -v zed >/dev/null || [[ -x $HOME/.local/bin/zed ]]; then
    ok "Zed ist bereits installiert"
    return
  fi
  msg "Zed-Editor (offizieller Installer, nur für deinen Benutzer)"
  curl -fsSL https://zed.dev/install.sh | sh || warn "Zed-Installation fehlgeschlagen – später erneut versuchen"
}

# ── eww (mit Wayland) ───────────────────────────────────────────────
# eww für X11 *und* Wayland (Layer-Shell). Ein vorhandenes ~/.local/bin/eww ohne
# Wayland wird ersetzt – es läuft damit unter X11 weiter wie bisher.
eww_has_wayland() {
  local bin
  for bin in "$HOME/.local/bin/eww" "$(command -v eww 2>/dev/null || true)"; do
    [[ -n $bin && -x $bin ]] && ldd "$bin" 2>/dev/null | grep -q 'gtk-layer-shell' && return 0
  done
  return 1
}

build_eww() {
  if eww_has_wayland; then
    ok "eww mit Wayland-Unterstützung ist bereits installiert"
    return
  fi
  if command -v eww >/dev/null || [[ -x $HOME/.local/bin/eww ]]; then
    warn "Vorhandenes eww kann kein Wayland – wird für X11 und Wayland neu gebaut"
  fi
  msg "eww $EWW_VERSION mit Wayland bauen (dauert einige Minuten)"
  rm -rf "$CACHE/eww"
  git clone --depth 1 --branch "$EWW_VERSION" https://github.com/elkowar/eww "$CACHE/eww"

  local cargo_bin features=(--no-default-features --features x11,wayland)
  cargo_bin=$(command -v cargo || true)
  if [[ -z $cargo_bin ]] || ! (cd "$CACHE/eww" && "$cargo_bin" build --release "${features[@]}"); then
    warn "Build mit System-Rust fehlgeschlagen – installiere aktuelles Rust über rustup (nur für deinen Benutzer)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
    cargo_bin="$HOME/.cargo/bin/cargo"
    (cd "$CACHE/eww" && "$cargo_bin" build --release "${features[@]}")
  fi
  install -Dm755 "$CACHE/eww/target/release/eww" "$HOME/.local/bin/eww"
  ok "eww installiert nach ~/.local/bin/eww (X11 und Wayland)"
}

# ── rofi (mit Wayland) ──────────────────────────────────────────────
# Ältere Distributionen liefern rofi nur für X11 – es liefe dann über XWayland.
# Ein eigener Build landet in einem eigenen Ordner, den nur die Sway-Sitzung
# benutzt (über ~/.config/sway/bin/rofi); alle anderen behalten das System-rofi.
rofi_has_wayland() {
  local bin
  for bin in "$ROFI_PREFIX/bin/rofi" "$(command -v rofi 2>/dev/null || true)"; do
    [[ -n $bin && -x $bin ]] && ldd "$bin" 2>/dev/null | grep -q 'libwayland-client' && return 0
  done
  return 1
}

build_rofi() {
  if rofi_has_wayland; then
    ok "rofi mit Wayland-Unterstützung ist vorhanden"
    return
  fi
  local t missing=()
  for t in meson ninja wayland-scanner pkg-config; do command -v "$t" >/dev/null || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    warn "rofi-Build übersprungen, es fehlt: ${missing[*]} – rofi läuft über XWayland"
    return
  fi
  msg "rofi $ROFI_VERSION mit Wayland bauen (etwa eine Minute)"
  local src="$CACHE/rofi-$ROFI_VERSION"
  rm -rf "$src"
  if ! curl -fsSL "https://github.com/davatorium/rofi/releases/download/$ROFI_VERSION/rofi-$ROFI_VERSION.tar.xz" |
       tar -xJ -C "$CACHE"; then
    warn "Download fehlgeschlagen – rofi läuft über XWayland"
    return
  fi
  if (cd "$src" &&
      { meson setup build --prefix="$ROFI_PREFIX" -Dwayland=enabled -Dxcb=disabled -Dcheck=disabled ||
        { rm -rf build; meson setup build --prefix="$ROFI_PREFIX"; }; } &&
      ninja -C build && ninja -C build install) && rofi_has_wayland; then
    ok "rofi mit Wayland installiert ($ROFI_PREFIX, nur für die Sway-Sitzung)"
  else
    warn "rofi-Build fehlgeschlagen – rofi läuft über XWayland"
  fi
}

# ── SwayFX (runde Ecken, Schatten, Unschärfe) – Pflicht ─────────────
# Bietet die Distribution kein SwayFX an (z. B. Ubuntu 24.04 / KDE neon) oder
# ist Sway schon installiert, wird SwayFX samt scenefx aus dem Quellcode gebaut.
# Installiert wird in einen eigenen Ordner (~/.local/share/i3-apple/swayfx-<tag>,
# Verweis „swayfx“). Nur die Sitzung „Sway (i3-apple)“ nimmt ihn in den PATH
# (env-sway.sh) – das System-Sway und die normale Sway-Sitzung bleiben unverändert.
#   1. Weg: die SwayFX-Version, die zur wlroots-Version des Systems passt
#      (libwlroots-*-dev); scenefx wird vorher einzeln dagegen gebaut.
#   2. Weg, falls das nicht klappt: eine aktuelle SwayFX-Version mit wlroots und
#      scenefx als meson-Unterprojekten – unabhängig vom wlroots des Systems.
# build_swayfx gibt 1 zurück, wenn beides scheitert; der Ablauf bricht dann ab.

# Gebautes SwayFX vorhanden und startfähig? (Nach einem System-Update kann die
# wlroots-Bibliothek fehlen, gegen die es gebaut wurde.)
swayfx_built_ok() {
  [[ -x $SWAYFX_PREFIX/bin/sway ]] && "$SWAYFX_PREFIX/bin/sway" --version >/dev/null 2>&1
}

# Weitere Pakete nach denselben Regeln wie install_packages: nur, was fehlt und
# verfügbar ist, jedes vorher simuliert, nie etwas entfernen.
apt_install_extra() { # <zweck> <paket> …
  local why=$1 p want=() keep=() list="$BACKUP_DIR/sway-apple-pakete-$TS.txt"
  shift
  for p in "$@"; do pkg_installed "$p" || want+=("$p"); done
  (( ${#want[@]} )) || return 0
  if (( ! ALLOW_APT )) || ! command -v apt-get >/dev/null || ! command -v sudo >/dev/null; then
    warn "$why: Pakete fehlen (${want[*]}) – ohne Paketinstallation wird es trotzdem versucht"
    return 1
  fi
  for p in "${want[@]}"; do
    pkg_available "$p" || continue          # nicht jede Distribution hat jedes -dev-Paket
    if apt_sim_ok "$p"; then keep+=("$p"); else warn "$why: übersprungen (würde andere Pakete entfernen): $p"; fi
  done
  (( ${#keep[@]} )) || return 0
  if ! apt_sim_ok "${keep[@]}"; then
    warn "$why: Die Pakete vertragen sich zusammen nicht – übersprungen (${keep[*]})"
    return 1
  fi
  apt_healthy || { apt_broken_hint; return 1; }
  mkdir -p "$BACKUP_DIR"
  [[ -f $list ]] || echo "# Von i3-apple (Sway) am $(date '+%d.%m.%Y %H:%M') installierte Pakete" > "$list"
  printf '%s\n' "${keep[@]}" >> "$list"
  sudo apt-get install "${APT_OPTS[@]}" "${keep[@]}"
}

# wlroots-Reihen, für die es ein -dev-Paket gibt oder die schon installiert sind,
# neueste zuerst. Ausgabe je Zeile: „<reihe> <paket>“ (Paket „-“ = schon da).
wlroots_candidates() {
  local p m v
  {
    for p in libwlroots-0.20-dev libwlroots-0.19-dev libwlroots-0.18-dev libwlroots-dev; do
      # awk liest bis zum Ende (kein exit) – sonst bräche apt-cache an SIGPIPE ab (pipefail)
      v=$(apt-cache show --no-all-versions "$p" 2>/dev/null | awk '/^Version:/ && !v { v = $2 } END { print v }') || v=""
      v=$(sed -E 's/^[0-9]+://; s/^([0-9]+\.[0-9]+).*/\1/' <<<"$v")
      [[ $v =~ ^[0-9]+\.[0-9]+$ ]] && echo "$v $p"
    done
    for m in wlroots-0.20 wlroots-0.19 wlroots-0.18 wlroots; do
      v=$(pkg-config --modversion "$m" 2>/dev/null) || continue
      echo "${v%.*} -"
    done
  } | sort -rV | awk '!seen[$1]++'
}

# Repo ohne Dateiinhalte klonen (die lädt git erst beim Auschecken) bzw. Tags holen
fx_repo() { # <url> <ziel>
  if [[ -d $2/.git ]]; then
    git -C "$2" fetch --quiet --tags --force origin
  else
    rm -rf "$2"
    git clone --quiet --filter=blob:none --no-checkout "$1" "$2"
  fi
}

# Neuester Versions-Tag, dessen meson.build die wlroots-Reihe verlangt.
# Sway, SwayFX und scenefx schreiben das als  wlroots_version = ['>=0.17.0', '<0.18.0']
# (teils über mehrere Zeilen verteilt – darum genügt „>=0.17.“ irgendwo; andere
# Abhängigkeiten haben keine Versionen im Bereich 0.17 … 0.20).
# <merkmal> muss außerdem im meson.build stehen: Die Repos sind Abspaltungen und
# enthalten auch Tags von Sway bzw. wlroots (z. B. „1.10“), die kein SwayFX sind.
fx_find_tag() { # <repo> <reihe> <merkmal>
  local tag mb re=">= ?${2//./\\.}\\."
  while IFS= read -r tag; do
    mb=$(git -C "$1" show "$tag:meson.build" 2>/dev/null) || continue
    if grep -qE "$re" <<<"$mb" && grep -qF -- "$3" <<<"$mb"; then echo "$tag"; return 0; fi
  done < <(git -C "$1" tag --sort=-v:refname | grep -E '^v?[0-9]+(\.[0-9]+)+$')
  return 1
}

# Neuester Tag einer Reihe (0.20 → 0.20.2) aus einer Tag-Liste auf stdin.
# sed statt head: liest bis zum Ende, sonst bräche sort an SIGPIPE ab (pipefail).
newest_in_series() { # <reihe>
  grep -E "^v?${1//./\\.}(\.[0-9]+)*$" | sort -rV | sed -n 1p
}

# wlroots-Reihe, die eine SwayFX-Version verlangt:  wlroots_version = ['>=0.20.0', …] → 0.20
fx_wlroots_series() { # <repo> <tag>
  git -C "$1" show "$2:meson.build" 2>/dev/null | grep -A2 -E '^wlroots_version' |
    grep -oE ">= ?0\.[0-9]+\." | sed -nE '1s/^>= ?(0\.[0-9]+)\.$/\1/p'
}

# scenefx-Tag zu einer SwayFX-Version. Neuere SwayFX nennen die Reihe selbst
# (dependency('scenefx-0.4', …)) – dann deren neuester Tag. Sonst der neueste
# scenefx-Tag, der dieselbe wlroots-Reihe verlangt.
fx_scenefx_tag() { # <swayfx-repo> <swayfx-tag> <scenefx-repo> <wlroots-reihe>
  local want tag
  want=$(git -C "$1" show "$2:meson.build" 2>/dev/null | grep -oE "scenefx-[0-9]+\.[0-9]+" |
         sed -n '1s/^scenefx-//p')
  if [[ -n $want ]]; then
    tag=$(git -C "$3" tag | newest_in_series "$want")
    [[ -n $tag ]] && { echo "$tag"; return 0; }
  fi
  fx_find_tag "$3" "$4" "'scenefx'"
}

# Eine Version bauen und nach <prefix> installieren. Optionen (name=wert), die es
# in dieser Version nicht gibt, fallen weg – sonst bricht meson ab.
# FX_SUBPROJECTS („name url tag“ je Eintrag) landen vor dem Bauen in subprojects/;
# meson baut und installiert sie dann mit (z. B. wlroots, wenn das System es nicht hat).
# rpath: sway findet libscenefx/libwlroots in <prefix>/lib ohne LD_LIBRARY_PATH.
FX_SUBPROJECTS=()
fx_build() { # <quelle> <tag> <build-ordner> <prefix> [name=wert …]
  local src=$1 tag=$2 build=$3 prefix=$4 o opts=() sub n u t
  shift 4
  git -C "$src" checkout --quiet --force --detach "$tag" || return 1
  # -ff: entfernt auch Unterprojekte eines früheren Versuchs (eigene Git-Repos) –
  # sonst nähme ein späterer Build gegen das System-wlroots sie trotzdem
  git -C "$src" clean -ffdxq || return 1
  for sub in "${FX_SUBPROJECTS[@]}"; do
    read -r n u t <<<"$sub"
    echo "── Unterprojekt $n $t"
    rm -rf "${src:?}/subprojects/$n"
    git clone --quiet --depth 1 --branch "$t" "$u" "$src/subprojects/$n" || return 1
  done
  # Mit Unterprojekten darf meson zu alte Systembibliotheken (z. B. xkbcommon) über
  # deren .wrap-Dateien nachladen – manche Systeme stellen das sonst ab
  (( ${#FX_SUBPROJECTS[@]} )) && opts+=(--wrap-mode=default)
  for o in "$@"; do
    grep -qs "option('${o%%=*}'" "$src/meson_options.txt" "$src/meson.options" && opts+=("-D$o")
  done
  echo "── $(basename "$src") $tag: meson ${opts[*]}"
  PKG_CONFIG_PATH="$prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
  LDFLAGS="-Wl,-rpath,$prefix/lib${LDFLAGS:+ $LDFLAGS}" \
    meson setup "$build" "$src" --prefix="$prefix" --libdir=lib --buildtype=release "${opts[@]}" || return 1
  ninja -C "$build" || return 1
  ninja -C "$build" install
}

SWAYFX_LOG="$CACHE/swayfx-build.log"

# SwayFX <fx_tag> in einen frischen Versionsordner bauen; der Verweis „swayfx“
# wechselt erst, wenn alles geklappt hat – ein Fehlschlag lässt eine ältere
# Fassung in Ruhe. Mit <wlroots-tag> kommen wlroots und scenefx als Unterprojekte
# mit, sonst wird scenefx vorher einzeln gegen das System-wlroots gebaut.
fx_install() { # <quelle-swayfx> <quelle-scenefx> <swayfx-tag> <scenefx-tag> [wlroots-tag]
  local src=$1 sfx_src=$2 fx_tag=$3 sfx_tag=$4 wl_tag=${5:-}
  local base="$HOME/.local/share/i3-apple" build="$CACHE/swayfx-build" ver old built=0
  local fx_opts=(man-pages=disabled default-wallpaper=false swaybar=false tray=disabled
                 zsh-completions=false bash-completions=false fish-completions=false)
  ver="$base/swayfx-${fx_tag#v}"
  rm -rf "$ver" "$build"
  mkdir -p "$base" "$build"
  if [[ -n $wl_tag ]]; then
    echo "══ SwayFX $fx_tag mit scenefx $sfx_tag und wlroots $wl_tag als Unterprojekte" >>"$SWAYFX_LOG"
    FX_SUBPROJECTS=("wlroots $WLROOTS_URL $wl_tag" "scenefx $SCENEFX_URL $sfx_tag")
    fx_build "$src" "$fx_tag" "$build/swayfx" "$ver" "${fx_opts[@]}" >>"$SWAYFX_LOG" 2>&1 && built=1
    FX_SUBPROJECTS=()
  else
    echo "══ SwayFX $fx_tag mit scenefx $sfx_tag gegen das System-wlroots" >>"$SWAYFX_LOG"
    fx_build "$sfx_src" "$sfx_tag" "$build/scenefx" "$ver" examples=false >>"$SWAYFX_LOG" 2>&1 &&
      fx_build "$src" "$fx_tag" "$build/swayfx" "$ver" "${fx_opts[@]}" >>"$SWAYFX_LOG" 2>&1 && built=1
  fi
  rm -rf "$build"
  # Startet das Ergebnis? (fehlende Bibliotheken zeigen sich erst hier – ins Protokoll)
  if (( built )) && "$ver/bin/sway" --version >>"$SWAYFX_LOG" 2>&1; then
    [[ -d $SWAYFX_PREFIX && ! -L $SWAYFX_PREFIX ]] && rm -rf "$SWAYFX_PREFIX"
    if ln -sfn "$ver" "$SWAYFX_PREFIX.neu" && mv -Tf "$SWAYFX_PREFIX.neu" "$SWAYFX_PREFIX"; then
      for old in "$base"/swayfx-*; do
        [[ $old == "$ver" ]] || rm -rf "$old"
      done
      ok "SwayFX installiert: $("$ver/bin/sway" --version 2>/dev/null | head -n1) (${ver/#$HOME/\~})"
      ok "Wirkt ab der nächsten Anmeldung in „Sway (i3-apple)“ – das System-Sway bleibt unverändert"
      return 0
    fi
    warn "SwayFX gebaut, aber der Verweis ${SWAYFX_PREFIX/#$HOME/\~} ließ sich nicht setzen"
  fi
  rm -rf "$ver"
  return 1
}

# Animationen (Fenster öffnen/schließen, verschieben, Arbeitsfläche wechseln)
# kann SwayFX erst ab dieser Version – ältere werden einmalig nachgerüstet.
FX_ANIM_MIN=0.6
FX_ANIM_FAILED="$CACHE/swayfx-animationen-fehlgeschlagen"

# Ist <tag> mindestens <version>? (leere Version = jede)
fx_tag_ok() { # <tag> <version>
  [[ -z $2 ]] && return 0
  [[ $(printf '%s\n%s\n' "$2" "${1#v}" | sort -V | sed -n 1p) == "$2" ]]
}

# Läuft wegen „if ! build_swayfx“ ohne set -e – jeder Schritt prüft selbst.
# Ist schon ein SwayFX da, aber ohne Animationen, wird eine neuere Version
# gebaut; scheitert das, bleibt die vorhandene in Gebrauch (Rückgabe 0) und
# derselbe Versuch wird erst bei einer neueren SwayFX-Version wiederholt.
build_swayfx() {
  local cur="" newest
  if swayfx_built_ok; then
    cur=$SWAYFX_PREFIX/bin/sway
  elif command -v sway >/dev/null && { sway --version 2>/dev/null | grep -qi swayfx || grep -qa corner_radius "$(command -v sway)"; }; then
    cur=$(command -v sway)
  fi
  if [[ -n $cur ]]; then
    ok "SwayFX ist vorhanden: $("$cur" --version 2>/dev/null | head -n1) (${cur/#$HOME/\~})"
    fx_has_animations "$cur" && { ok "SwayFX kann Animationen"; return 0; }
    # Erst vor Kurzem gescheitert? Dann nicht bei jedem Lauf Pakete prüfen und
    # Quellen holen – nach einer Woche wird nach einer neueren Version gesehen
    if [[ -f $FX_ANIM_FAILED && -z $(find "$FX_ANIM_FAILED" -mtime +6 2>/dev/null) ]]; then
      warn "Animationen: SwayFX $(cat "$FX_ANIM_FAILED") ließ sich zuletzt nicht bauen – übersprungen"
      warn "Erneut versuchen: rm ${FX_ANIM_FAILED/#$HOME/\~} und den Installer noch einmal starten"
      return 0
    fi
    fx_prepare "SwayFX $FX_ANIM_MIN+ mit Animationen bauen (dauert einige Minuten)" ||
      { warn "Animationen: SwayFX lässt sich nicht nachrüsten – die vorhandene Version bleibt"; return 0; }
    newest=$(git -C "$CACHE/swayfx-src" tag --sort=-v:refname | grep -E '^v?[0-9]+(\.[0-9]+)+$' | sed -n 1p)
    if [[ -z $newest ]] || ! fx_tag_ok "$newest" "$FX_ANIM_MIN"; then
      warn "Animationen: keine SwayFX-Version ab $FX_ANIM_MIN gefunden – die vorhandene bleibt"
      return 0
    fi
    if [[ $(cat "$FX_ANIM_FAILED" 2>/dev/null) == "$newest" ]]; then
      touch "$FX_ANIM_FAILED"   # noch keine neuere Version – wieder eine Woche Ruhe
      warn "Animationen: SwayFX $newest ließ sich schon einmal nicht bauen – übersprungen"
      warn "Erneut versuchen: rm ${FX_ANIM_FAILED/#$HOME/\~} und den Installer noch einmal starten"
      return 0
    fi
    if fx_try "$FX_ANIM_MIN"; then rm -f "$FX_ANIM_FAILED"; return 0; fi
    echo "$newest" > "$FX_ANIM_FAILED"
    warn "Animationen: Bau fehlgeschlagen – SwayFX bleibt bei der vorhandenen Version"
    grep -E '^══|ERROR|[Ee]rror:|fatal:|NO found' "$SWAYFX_LOG" | tail -n 20 | sed 's/^/      /'
    warn "Vollständiges Protokoll: $SWAYFX_LOG"
    return 0
  fi

  [[ -e $SWAYFX_PREFIX || -L $SWAYFX_PREFIX ]] &&
    warn "Selbst gebautes SwayFX startet nicht mehr (System-Update?) – wird neu gebaut"
  fx_prepare "SwayFX bauen (runde Ecken, Schatten, Unschärfe, Animationen – dauert einige Minuten)" || return 1
  # Zuerst eine Version mit Animationen, sonst irgendeine, die sich bauen lässt
  fx_try "$FX_ANIM_MIN" && return 0
  warn "SwayFX mit Animationen ließ sich nicht bauen – versuche ältere Versionen"
  fx_try "" && return 0

  # Je Versuch die Kopfzeile und seine Fehler – das Protokollende zeigt nur den letzten
  warn "SwayFX ließ sich nicht bauen. Versuche und Fehler:"
  grep -E '^══|ERROR|[Ee]rror:|fatal:|NO found' "$SWAYFX_LOG" | tail -n 40 | sed 's/^/      /'
  warn "Vollständiges Protokoll: $SWAYFX_LOG"
  return 1
}

# Build-Pakete, Werkzeuge und Quellen (swayfx-src, scenefx-src) bereitstellen.
fx_prepare() { # <überschrift>
  msg "$1"
  mkdir -p "$CACHE"
  : > "$SWAYFX_LOG"
  FX_TRIED=()

  # Build-Abhängigkeiten, auch für wlroots als Unterprojekt (fehlende -dev-Pakete
  # einer Distribution werden übersprungen; was wirklich fehlt, meldet meson im Protokoll)
  local deps=(meson ninja-build pkg-config build-essential git cmake
    libwayland-dev libwayland-bin wayland-protocols libxkbcommon-dev libpixman-1-dev
    libdrm-dev libgbm-dev libegl-dev libgles-dev libgles2-mesa-dev libinput-dev libevdev-dev libudev-dev
    libseat-dev libdisplay-info-dev liblcms2-dev libliftoff-dev
    libjson-c-dev libpcre2-dev libpango1.0-dev libcairo2-dev libgdk-pixbuf-2.0-dev
    libxcb1-dev libxcb-icccm4-dev libxcb-res0-dev libxcb-composite0-dev libxcb-xfixes0-dev
    libxcb-dri3-dev libxcb-present-dev libxcb-render-util0-dev libxcb-ewmh-dev libxcb-errors-dev
    libxcb-shm0-dev xwayland hwdata)
  apt_install_extra "SwayFX" "${deps[@]}" || true

  local t missing=()
  for t in git meson ninja pkg-config cc; do command -v "$t" >/dev/null || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    warn "SwayFX kann nicht gebaut werden, es fehlt: ${missing[*]}"
    return 1
  fi

  local src="$CACHE/swayfx-src" sfx_src="$CACHE/scenefx-src"
  if ! fx_repo "$SWAYFX_URL" "$src" >>"$SWAYFX_LOG" 2>&1 || ! fx_repo "$SCENEFX_URL" "$sfx_src" >>"$SWAYFX_LOG" 2>&1; then
    warn "SwayFX/scenefx ließ sich nicht herunterladen (Internetverbindung?)"
    return 1
  fi
}

# Wurde diese Kombination in diesem Lauf schon gebaut (und ist gescheitert)?
FX_TRIED=()
fx_tried() { # <schlüssel> – merkt ihn sich, Rückgabe 0 = schon versucht
  local k
  for k in "${FX_TRIED[@]}"; do [[ $k == "$1" ]] && return 0; done
  FX_TRIED+=("$1")
  return 1
}

# Beide Wege durchprobieren, nur SwayFX-Versionen ab <mindestversion> (leer = alle).
fx_try() { # <mindestversion>
  local min=$1 src="$CACHE/swayfx-src" sfx_src="$CACHE/scenefx-src"

  # 1. Weg: passend zur wlroots-Reihe des Systems (neueste Reihe zuerst)
  local fx_tag sfx_tag wl wl_tag wl_tags s p seen=()
  while read -r s p; do
    seen+=("$s")
    fx_tag=$(fx_find_tag "$src" "$s" "scenefx") || continue        # SwayFX hängt von scenefx ab
    fx_tag_ok "$fx_tag" "$min" || continue
    fx_tried "$fx_tag system-$s" && continue
    sfx_tag=$(fx_scenefx_tag "$src" "$fx_tag" "$sfx_src" "$s") || continue
    ok "Passend zu wlroots $s des Systems: SwayFX $fx_tag mit scenefx $sfx_tag"
    # </dev/null: Nichts im Schleifenrumpf darf die Kandidatenliste (stdin) lesen
    if [[ $p != - ]]; then
      apt_install_extra "SwayFX" "$p" </dev/null || true
      pkg_installed "$p" || { warn "$p ließ sich nicht installieren"; continue; }
    fi
    fx_install "$src" "$sfx_src" "$fx_tag" "$sfx_tag" </dev/null && return 0
    warn "Build gegen wlroots $s fehlgeschlagen"
  done < <(wlroots_candidates)
  (( ${#seen[@]} )) || [[ -n $min ]] || warn "Kein wlroots-Entwicklungspaket im System gefunden"

  # 2. Weg: wlroots und scenefx als Unterprojekte – die drei neuesten SwayFX-Versionen
  #    (eine neuere scheitert evtl. an zu alten Systembibliotheken, dann die nächste).
  #    Tags ohne „scenefx“ im meson.build sind Sway-Tags der Abspaltung und zählen nicht.
  local tries=0 mb
  wl_tags=$(git ls-remote --tags --refs "$WLROOTS_URL" 2>>"$SWAYFX_LOG" | sed 's#.*refs/tags/##')
  if [[ -z $wl_tags ]]; then
    warn "wlroots-Versionen ließen sich nicht abfragen ($WLROOTS_URL)"
  else
    while read -r fx_tag; do
      (( tries < 3 )) || break
      # erst einlesen, dann prüfen: grep -q in der Pipe gäbe mit pipefail SIGPIPE-Fehler
      mb=$(git -C "$src" show "$fx_tag:meson.build" 2>/dev/null) || continue
      grep -qF scenefx <<<"$mb" || continue
      fx_tag_ok "$fx_tag" "$min" || continue
      tries=$((tries + 1))
      wl=$(fx_wlroots_series "$src" "$fx_tag")
      [[ -n $wl ]] || continue
      wl_tag=$(newest_in_series "$wl" <<<"$wl_tags")
      sfx_tag=$(fx_scenefx_tag "$src" "$fx_tag" "$sfx_src" "$wl")
      [[ -n $wl_tag && -n $sfx_tag ]] || continue
      fx_tried "$fx_tag eigen-$wl_tag" && continue
      ok "Versuche SwayFX $fx_tag mit eigenem wlroots $wl_tag und scenefx $sfx_tag"
      fx_install "$src" "$sfx_src" "$fx_tag" "$sfx_tag" "$wl_tag" </dev/null && return 0
      warn "Build von SwayFX $fx_tag fehlgeschlagen"
    done < <(git -C "$src" tag --sort=-v:refname | grep -E '^v?[0-9]+(\.[0-9]+)+$')
  fi
  return 1
}

# ── Themes ──────────────────────────────────────────────────────────
# Nur Dateien in ~/.themes und ~/.local/share/icons – andere Desktops sehen die
# Themes zur Auswahl, benutzen sie aber nicht. Bewusst OHNE WhiteSurs Option -l:
# die schreibt nach ~/.config/gtk-4.0 und würde GTK4-Apps in GNOME/Plasma umfärben.
clone_or_update() { # <url> <ziel>
  if [[ -d $2/.git ]]; then
    git -C "$2" pull --ff-only --quiet || true
  else
    git clone --depth 1 "$1" "$2"
  fi
}

install_themes() {
  msg "WhiteSur GTK-Theme (macOS-Look für Apps)"
  clone_or_update https://github.com/vinceliuice/WhiteSur-gtk-theme "$CACHE/WhiteSur-gtk-theme"
  local tool missing=()
  # Fehlt ein Werkzeug, würde WhiteSurs eigenes Skript selbst apt aufrufen –
  # an den Sicherheitsregeln vorbei. Dann lieber auslassen.
  for tool in sassc glib-compile-resources xmllint; do
    command -v "$tool" >/dev/null || missing+=("$tool")
  done
  if (( ${#missing[@]} )); then
    warn "WhiteSur-GTK übersprungen, es fehlt: ${missing[*]} (Pakete sassc, libglib2.0-dev-bin, libxml2-utils)"
  else
    (cd "$CACHE/WhiteSur-gtk-theme" && ./install.sh) || warn "WhiteSur-GTK-Installation meldete einen Fehler"
  fi

  msg "WhiteSur Icon-Theme"
  clone_or_update https://github.com/vinceliuice/WhiteSur-icon-theme "$CACHE/WhiteSur-icon-theme"
  (cd "$CACHE/WhiteSur-icon-theme" && ./install.sh) || warn "WhiteSur-Icon-Installation meldete einen Fehler"

  # Fehlt WhiteSur ein Statussymbol, soll das Adwaita-Symbol erscheinen statt einer Lücke
  local idx
  for idx in "$HOME"/.local/share/icons/WhiteSur*/index.theme; do
    [[ -f $idx ]] || continue
    grep -q '^Inherits=.*Adwaita' "$idx" && continue
    if grep -q '^Inherits=' "$idx"; then
      sed -i 's/^Inherits=\(.*\)$/Inherits=\1,Adwaita/' "$idx"
    else
      sed -i 's/^\[Icon Theme\]$/[Icon Theme]\nInherits=Adwaita,hicolor/' "$idx"
    fi
  done

  install_cursor
}

# macOS-Cursor als zusätzliches Cursor-Theme (wird NICHT als Standard gesetzt)
install_cursor() {
  local icons="$HOME/.local/share/icons" url tmp d
  if [[ -d $icons/macOS/cursors ]]; then ok "macOS-Cursor bereits vorhanden"; return; fi
  msg "macOS-Cursor (apple_cursor)"
  url=$(curl -fsSL https://api.github.com/repos/ful1e5/apple_cursor/releases/latest |
        jq -r '.assets[].browser_download_url' | grep -E '/macOS\.tar\.(xz|gz)$' | head -n1 || true)
  if [[ -z $url ]]; then
    url=$(curl -fsSL https://api.github.com/repos/ful1e5/apple_cursor/releases/latest |
          jq -r '.assets[].browser_download_url' | grep -E 'macOS[^/]*\.tar\.(xz|gz)$' | grep -vi white | head -n1 || true)
  fi
  [[ -n $url ]] || { warn "Cursor-Download nicht gefunden – übersprungen"; return; }

  tmp=$(mktemp -d "$CACHE/cursor.XXXX")
  curl -fsSL "$url" -o "$tmp/cursor.tar"
  tar -xf "$tmp/cursor.tar" -C "$tmp"
  mkdir -p "$icons"
  while IFS= read -r d; do
    d=$(dirname "$d")
    [[ $(basename "$d") == default ]] && continue   # niemals den Standard-Cursor ersetzen
    rm -rf "${icons:?}/$(basename "$d")"
    cp -r "$d" "$icons/"
    ok "Cursor-Theme $(basename "$d") installiert"
  done < <(find "$tmp" -mindepth 2 -maxdepth 3 -name index.theme)

  # Einheitlicher Name „macOS“, falls das Release anders heißt (z. B. macOS-Monterey)
  if [[ ! -d $icons/macOS ]]; then
    d=$(find "$icons" -maxdepth 1 -type d -name 'macOS*' ! -iname '*white*' | head -n1)
    [[ -n $d ]] && ln -sfn "$d" "$icons/macOS"
  fi
  rm -rf "$tmp"
}

# ── Konfiguration ───────────────────────────────────────────────────
backup() { # sichert eine bestehende Datei/Ordner, der nicht von i3-apple stammt
  if [[ -e $1 || -L $1 ]]; then
    mv "$1" "$1.bak-$TS"
    warn "Gesichert: $1 → $1.bak-$TS"
  fi
}

# Startet die Sitzung SwayFX? Das selbst gebaute hat Vorrang (env-sway.sh), sonst
# das System-Sway: an der Versionszeile erkannt oder am Programm (nur SwayFX kennt corner_radius)
is_swayfx() {
  local bin
  swayfx_built_ok && return 0
  bin=$(command -v sway) || return 1
  sway --version 2>/dev/null | grep -qi swayfx || grep -qa corner_radius "$bin"
}

# Soll fx.conf die SwayFX-Befehle bekommen? Läuft Sway gerade, entscheidet das
# laufende Programm – sonst meldete das Neuladen am Ende unbekannte Befehle,
# wenn SwayFX eben erst gebaut wurde. Beim nächsten Anmelden schreibt
# env-sway.sh fx.conf ohnehin neu.
fx_wanted() {
  local pid exe
  if [[ -n ${SWAYSOCK:-} ]]; then
    pid=$(pgrep -u "$UID" -x sway | head -n1 || true)
    exe=$([[ -n $pid ]] && readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    if [[ -n $exe ]]; then grep -qa corner_radius "$exe"; return; fi
  fi
  is_swayfx
}

# Kennt das Sway, für das fx.conf gilt, Animationen (SwayFX ab 0.6)? Gleiche
# Reihenfolge wie fx_wanted: laufendes Programm, sonst das der nächsten Anmeldung.
fx_animations_wanted() {
  local pid exe=""
  if [[ -n ${SWAYSOCK:-} ]]; then
    pid=$(pgrep -u "$UID" -x sway | head -n1 || true)
    exe=$([[ -n $pid ]] && readlink -f "/proc/$pid/exe" 2>/dev/null || true)
  fi
  if [[ -z $exe ]]; then
    if swayfx_built_ok; then exe=$SWAYFX_PREFIX/bin/sway; else exe=$(command -v sway || true); fi
  fi
  [[ -n $exe ]] && fx_has_animations "$exe"
}
fx_has_animations() { grep -qa animation_duration_ms "$1" 2>/dev/null; }

# kitty_at_least <version>: installiertes kitty ist mindestens so neu
kitty_at_least() {
  local v
  v=$(kitty --version 2>/dev/null | awk '{print $2}')
  [[ -n $v && $(printf '%s\n%s\n' "$1" "$v" | sort -V | head -n1) == "$1" ]]
}

# ── Dateien aktualisieren, ohne eigene Änderungen zu verlieren ──────
# Für jeden Zielordner merkt sich der Installer in einer Prüfsummenliste, welche
# Fassung er zuletzt installiert hat. Beim nächsten Lauf gilt je Datei:
#   • unverändert seit der letzten Installation → neue Fassung einspielen
#   • von dir geändert, im Repo gleich geblieben → deine Fassung bleibt
#   • von dir UND im Repo geändert → deine Fassung wird gesichert
#     (~/.config/i3-apple/lokale-aenderungen/<Datum>/), die neue eingespielt
#   • eigene, zusätzliche Dateien bleiben immer liegen
KEEP="$CFG/i3-apple/lokale-aenderungen/$TS"

sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# merge_tree <neue-dateien> <ziel> <prüfsummenliste> <entfernte-löschen:0|1>
merge_tree() {
  local new=$1 dst=$2 man=$3 prune=$4 f rel cur old fresh line
  local updated=0 kept=() saved=() fresh_install=0
  local -A last=()
  if [[ -f $man ]]; then
    while IFS= read -r line; do [[ -n $line ]] && last[${line#*  }]=${line%%  *}; done < "$man"
  else
    fresh_install=1
  fi
  mkdir -p "$dst"
  : > "$man.new"
  while IFS= read -r -d '' f; do
    rel=${f#"$new"/}
    fresh=$(sha "$f")
    printf '%s  %s\n' "$fresh" "$rel" >> "$man.new"
    if [[ ! -e $dst/$rel ]]; then
      install -D -m "$(stat -c %a "$f")" "$f" "$dst/$rel"; updated=$((updated + 1)); continue
    fi
    cur=$(sha "$dst/$rel")
    old=${last[$rel]:-}
    if [[ $cur == "$fresh" ]]; then
      chmod --reference="$f" "$dst/$rel"; continue          # schon aktuell
    fi
    if [[ -n $old && $cur == "$old" ]]; then                 # nicht angefasst → aktualisieren
      install -m "$(stat -c %a "$f")" "$f" "$dst/$rel"; updated=$((updated + 1)); continue
    fi
    if [[ -n $old && $fresh == "$old" ]]; then               # nur du hast geändert → bleibt
      kept+=("$rel"); continue
    fi
    # beide geändert (oder ältere Installation ohne Liste): deine Fassung sichern
    install -D -m 644 "$dst/$rel" "$KEEP/${dst#"$HOME"/}/$rel"
    install -m "$(stat -c %a "$f")" "$f" "$dst/$rel"
    saved+=("$rel"); updated=$((updated + 1))
  done < <(find "$new" -type f -print0 | sort -z)

  # Dateien, die es im Repo nicht mehr gibt: nur entfernen, wenn unverändert
  if (( prune )); then
    for rel in "${!last[@]}"; do
      [[ -e $new/$rel || ! -f $dst/$rel ]] && continue
      if [[ $(sha "$dst/$rel") == "${last[$rel]}" ]]; then rm -f "$dst/$rel"; else kept+=("$rel"); fi
    done
  fi
  mv "$man.new" "$man"

  (( updated )) && ok "${dst/#$HOME/\~}: $updated Datei(en) aktualisiert"
  local r
  for r in "${kept[@]}"; do ok "Deine Änderung bleibt: ${dst/#$HOME/\~}/$r"; done
  if (( ${#saved[@]} )); then
    if (( fresh_install )); then
      warn "Bisherige Fassungen von ${#saved[@]} Datei(en) gesichert in ${KEEP/#$HOME/\~}"
    else
      for r in "${saved[@]}"; do
        warn "Von dir UND im Repo geändert – deine Fassung gesichert: ${KEEP/#$HOME/\~}/${dst#"$HOME"/}/$r"
      done
    fi
  fi
}

# Baut die Sway-Konfiguration in einem leeren Ordner zusammen (wie sie installiert wird)
# Alles kommt aus sway/config/sway – keine Dateien von außerhalb dieses Ordners.
build_sway_tree() {
  local out=$1
  cp -r "$SWAY/config/sway/." "$out/"
  sed -i "s#@EWW@#$CFG/sway/eww#g" "$out/eww/eww.yuck"
  # rofi-Konfiguration verweist auf das eigene Theme (absoluter Pfad)
  sed -i "s#@SWAY@#$CFG/sway#g" "$out/rofi/config.rasi"
  # kitty: SF Mono verwenden, wenn vorhanden – sonst JetBrains Mono
  if ! fc-list 2>/dev/null | grep -qi 'SF Mono'; then
    sed -i 's/^font_family .*/font_family      JetBrains Mono/' "$out/kitty/kitty.conf"
    warn "SF Mono nicht gefunden – kitty nutzt in Sway JetBrains Mono"
  fi
  # kitty ab 0.36: Zeiger blendet weich ein und aus (ältere Versionen
  # kennen die Schreibweise nicht und würden einen Fehler melden)
  if kitty_at_least 0.36.0; then
    sed -i 's/^cursor_blink_interval .*/cursor_blink_interval 0.5 ease-in-out/' "$out/kitty/kitty.conf"
  fi
  chmod 755 "$out"/scripts/*.sh "$out"/scripts/*.py "$out"/bin/* \
            "$out"/eww/scripts/*.sh "$out"/eww/scripts/*.py
}

deploy() {
  msg "Konfiguration nach $CFG/sway übernehmen (eigene Änderungen bleiben erhalten)"
  local stage

  # Sway mit Skripten, Menüleiste, rofi, dunst und kitty – alles in ~/.config/sway.
  # Die gleichnamigen Ordner in ~/.config (rofi, dunst, kitty) bleiben unberührt.
  # Eine fremde Sway-Konfiguration (nicht von i3-apple) wird zuerst beiseitegelegt.
  if [[ -e $CFG/sway && ! -e $CFG/sway/.i3-apple ]]; then backup "$CFG/sway"; fi
  mkdir -p "$CFG/i3-apple"
  stage=$(mktemp -d "$CACHE/sway-stage.XXXX")
  build_sway_tree "$stage"
  merge_tree "$stage" "$CFG/sway" "$CFG/i3-apple/.sway-installiert.sha256" 1
  rm -rf "$stage"
  touch "$CFG/sway/.i3-apple"

  # Eigene Sway-Ergänzungen: wird nur angelegt, nie überschrieben
  if [[ ! -f $CFG/i3-apple/sway-user.conf ]]; then
    cat > "$CFG/i3-apple/sway-user.conf" <<'EOF'
# i3-apple · eigene Sway-Anpassungen (wird am Ende von ~/.config/sway/config geladen)
# Diese Datei überschreibt der Installer nie. Beispiele:
#   bindsym $mod+Shift+Return exec firefox --private-window
#   for_window [app_id="org.gnome.Nautilus"] floating enable
#   input type:keyboard xkb_layout de
EOF
    ok "Für eigene Anpassungen: ~/.config/i3-apple/sway-user.conf"
  fi

  # SwayFX ist an dieser Stelle vorhanden (build_swayfx bricht sonst vorher ab).
  # Läuft gerade noch ein normales Sway, bleibt fx.conf bis zur nächsten Anmeldung
  # leer – das Neuladen am Ende würde die Befehle sonst als unbekannt melden.
  if fx_wanted; then
    cp "$CFG/sway/fx-effects.conf" "$CFG/sway/fx.conf"
    ok "SwayFX: Unschärfe, Schatten, runde Ecken"
    if fx_animations_wanted; then
      cat "$CFG/sway/fx-animations.conf" >> "$CFG/sway/fx.conf"
      ok "SwayFX: Animationen (Fenster, Arbeitsflächen)"
    elif is_swayfx && fx_has_animations "$(swayfx_built_ok && echo "$SWAYFX_PREFIX/bin/sway" || command -v sway)"; then
      ok "SwayFX mit Animationen ist bereit – sie wirken ab der nächsten Anmeldung"
    fi
  else
    : > "$CFG/sway/fx.conf"
    ok "SwayFX ist bereit – Unschärfe, Schatten und runde Ecken ab der nächsten Anmeldung"
  fi
  ok "Menüleiste, rofi, dunst und kitty (nur für Sway, in ~/.config/sway)"

  # kitty-Farben passend zu Hell/Dunkel; danach hält theme.sh die Datei aktuell
  if [[ ! -f $CFG/sway/kitty/theme.conf ]]; then
    local mode
    mode=$(cat "$CFG/i3-apple/mode" 2>/dev/null)
    [[ $mode == light ]] || mode=dark
    printf '# Von theme.sh geschrieben (Hell/Dunkel) – nicht von Hand ändern\ninclude colors-%s.conf\n' \
      "$mode" > "$CFG/sway/kitty/theme.conf"
  fi

  # X-Apps (XWayland) lesen die GTK-Einstellungen über eine eigene xsettingsd-Datei
  mkdir -p "$CFG/i3-apple"
  [[ -f $CFG/i3-apple/xsettingsd.conf ]] || cp "$SWAY/home/xsettingsd.conf" "$CFG/i3-apple/xsettingsd.conf"
}

# Sitzung „Sway (i3-apple)“ am Anmeldebildschirm: lädt env-sway.sh, dann Sway.
# Neue Dateien – vorhandene Sitzungen (GNOME, Plasma, Sway …) bleiben unverändert.
install_session_files() {
  local wrapper=/usr/local/bin/sway-apple-session
  local desktop=/usr/share/wayland-sessions/sway-apple.desktop
  if cmp -s "$SWAY/home/sway-apple-session" "$wrapper" && cmp -s "$SWAY/home/sway-apple.desktop" "$desktop"; then
    ok "Sitzung „Sway (i3-apple)“ ist eingetragen"
    return
  fi
  local f
  for f in "$wrapper" "$desktop"; do
    if [[ -e $f ]] && ! grep -q 'i3-apple' "$f"; then
      warn "$f gehört nicht zu i3-apple – Sitzung nicht eingetragen"
      return
    fi
  done
  msg "Sitzung „Sway (i3-apple)“ für den Anmeldebildschirm eintragen (Root-Rechte)"
  local root=()
  if (( EUID == 0 )); then root=()
  elif command -v sudo >/dev/null; then root=(sudo)
  elif command -v doas >/dev/null; then root=(doas)
  else
    warn "Weder sudo noch doas vorhanden – Sitzung nicht eingetragen. Als root nachholen:"
    printf '      su -c "install -Dm755 %q %q && install -Dm644 %q %q"\n' \
      "$SWAY/home/sway-apple-session" "$wrapper" "$SWAY/home/sway-apple.desktop" "$desktop"
    return 0
  fi
  if "${root[@]}" install -Dm755 "$SWAY/home/sway-apple-session" "$wrapper" &&
     "${root[@]}" install -Dm644 "$SWAY/home/sway-apple.desktop" "$desktop"; then
    ok "$desktop"
  else
    warn "Sitzung konnte nicht eingetragen werden – später mit Root-Rechten nachholen (siehe sway/README.md)"
  fi
}

# dunst bringt einen D-Bus-Dienst für Mitteilungen mit. In Plasma/GNOME könnte
# er beim Anmelden schneller sein als der eigene Mitteilungsdienst und die
# Mitteilungen „stehlen“. Dieser Eintrag (hat Vorrang vor den Systemdateien)
# startet dunst nur in Sway und reicht sonst an den Dienst des Desktops weiter.
install_notification_guard() {
  local dir="$DATA/dbus-1/services" helper="$DATA/i3-apple/notifications-activate"
  mkdir -p "$dir" "$DATA/i3-apple"
  install -m755 "$SWAY/home/notifications-activate" "$helper"
  printf '[D-BUS Service]\n# i3-apple: dunst nur in Sway, sonst der Dienst des Desktops\nName=org.freedesktop.Notifications\nExec=%s\n' \
    "$helper" > "$dir/org.freedesktop.Notifications.i3-apple.service"
  ok "Mitteilungen: dunst nur in Sway, Plasma/GNOME behalten ihren eigenen Dienst"
}

# Eigene dconf-Datenbank der Sway-Sitzung mit Theme, Symbolen, Cursor und Schrift
# füllen. Ohne diese Werte nimmt GTK (und damit die Menüleiste) „Adwaita“ – auf
# KDE-Systemen fehlen dann viele Symbole. Klappt ohne laufende Sitzung: ist kein
# dconf-Dienst erreichbar, wird die Datenbank direkt geschrieben (dconf compile).
seed_dconf() {
  local prof="$CFG/i3-apple/dconf-profile" db="$CFG/dconf/i3apple-sway" mode gtk icons scheme kf
  if ! command -v dconf >/dev/null; then
    warn "dconf fehlt (Paket dconf-cli) – GTK-Theme der Sitzung setzt erst theme.sh beim Start"
    return 0
  fi
  mode=$(cat "$CFG/i3-apple/mode" 2>/dev/null || echo dark)
  if [[ $mode == light ]]; then gtk=WhiteSur-Light icons=WhiteSur scheme=prefer-light
  else gtk=WhiteSur-Dark icons=WhiteSur-dark scheme=prefer-dark; fi

  local cur
  cur=$(DCONF_PROFILE="$prof" dconf read /org/gnome/desktop/interface/icon-theme 2>/dev/null)
  if [[ $cur == *WhiteSur* ]]; then ok "GTK-Einstellungen der Sitzung: $cur"; return 0; fi

  kf=$(mktemp -d "$CACHE/dconf.XXXX")
  cat > "$kf/i3apple" <<EOF
[org/gnome/desktop/interface]
gtk-theme='$gtk'
icon-theme='$icons'
color-scheme='$scheme'
cursor-theme='macOS'
cursor-size=24
font-name='SF Pro Text 10'

[org/gnome/desktop/wm/preferences]
button-layout='close,minimize,maximize:'
EOF
  if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] &&
     (cd / && DCONF_PROFILE="$prof" timeout 10 dconf load / < "$kf/i3apple") 2>/dev/null &&
     [[ $(DCONF_PROFILE="$prof" dconf read /org/gnome/desktop/interface/icon-theme) == *WhiteSur* ]]; then
    ok "GTK-Einstellungen der Sitzung gesetzt ($gtk, $icons)"
  elif [[ ! -f $db ]]; then
    # Datenbank gibt es noch nicht → direkt erzeugen (überschreibt also nichts)
    mkdir -p "$CFG/dconf"
    if dconf compile "$db" "$kf"; then
      ok "GTK-Einstellungen der Sitzung geschrieben ($gtk, $icons)"
    else
      warn "GTK-Einstellungen der Sitzung konnten nicht geschrieben werden – theme.sh setzt sie beim Start"
    fi
  else
    # Vorhandene Datenbank nie ersetzen (enthält evtl. eigene Einstellungen)
    warn "Symbol-Theme der Sitzung ist noch nicht WhiteSur – theme.sh setzt es beim nächsten Anmelden"
  fi
  rm -rf "$kf"
}

# Fehlt WhiteSur ein Symbol, soll ein vorhandenes Ersatz-Theme einspringen statt einer
# Lücke – Adwaita (GNOME) oder Breeze (KDE). Nur die eigenen WhiteSur-Dateien in
# ~/.local/share/icons werden angepasst.
icon_fallbacks() {
  local idx fb t
  for idx in "$HOME"/.local/share/icons/WhiteSur*/index.theme; do
    [[ -f $idx ]] || continue
    fb=""
    for t in Adwaita breeze-dark breeze hicolor; do
      grep -q "^Inherits=.*\b$t\b" "$idx" || fb+=",$t"
    done
    [[ -z $fb ]] && continue
    if grep -q '^Inherits=' "$idx"; then
      sed -i "s/^Inherits=\(.*\)$/Inherits=\1$fb/" "$idx"
    else
      sed -i "s/^\[Icon Theme\]$/[Icon Theme]\nInherits=${fb#,}/" "$idx"
    fi
  done
  command -v gtk-update-icon-cache >/dev/null &&
    for idx in "$HOME"/.local/share/icons/WhiteSur*/; do gtk-update-icon-cache -qf "$idx" 2>/dev/null; done
  return 0
}

# Eigenes Symbol-Theme der Menüleiste (~/.local/share/icons/i3apple-sway-bar, in keiner
# Theme-Auswahl sichtbar). eww.scss legt die Leiste darauf fest – unabhängig davon,
# was GTK über die dconf-Datenbank der Sitzung bekommt. Fehlende GNOME-Symbolnamen
# werden aus Breeze/Adwaita ergänzt. Muss nach deploy laufen (Skript in ~/.config/sway).
bar_icons() {
  local out rc=0
  out=$(python3 "$CFG/sway/eww/scripts/bar-icons.py" 2>&1) || rc=$?
  if (( rc == 0 )); then ok "$out"; else warn "${out:-bar-icons.py fehlgeschlagen (Code $rc)}"; fi
}

setup_session() {
  msg "Sitzung einrichten (Umgebung, Bildschirmprofile, Hintergrund)"
  mkdir -p "$CFG/i3-apple/wallpapers"
  # Umgebung der Sitzung und eigene dconf-Datenbank – über denselben Abgleich wie
  # ~/.config/sway, damit eigene Änderungen an env-sway.sh nicht verloren gehen.
  # Alle anderen Dateien in ~/.config/i3-apple (Profile, Hintergründe, Favoriten,
  # Hell/Dunkel …) fasst der Installer nicht an.
  local stage
  stage=$(mktemp -d "$CACHE/home-stage.XXXX")
  cp "$SWAY/home/env-sway.sh" "$stage/env-sway.sh"
  printf 'user-db:i3apple-sway\n' > "$stage/dconf-profile"
  merge_tree "$stage" "$CFG/i3-apple" "$CFG/i3-apple/.sway-home-installiert.sha256" 0
  rm -rf "$stage"
  seed_dconf
  icon_fallbacks
  bar_icons
  # Favoriten & Eingabegeräte nur anlegen, nie überschreiben
  [[ -f $CFG/i3-apple/favorites ]] || cp "$SWAY/home/favorites" "$CFG/i3-apple/favorites"
  [[ -f $CFG/i3-apple/input ]]     || cp "$SWAY/home/input"     "$CFG/i3-apple/input"

  install_session_files
  install_notification_guard

  # Bildschirmprofile → kanshi (läuft nur in Sway). Nur anlegen, wenn es noch keine
  # kanshi-Konfiguration gibt – vorhandene schreibt nur das Bildschirm-Fenster neu
  # (aus den gespeicherten Profilen; eine fremde wird dabei vorher gesichert).
  if [[ -f $CFG/kanshi/config && $(head -n1 "$CFG/kanshi/config") != "# i3-apple"* ]]; then
    warn "Eigene kanshi-Konfiguration gefunden – wird beim ersten Speichern eines Profils gesichert und ersetzt"
  elif [[ -f $CFG/kanshi/config ]]; then
    ok "kanshi-Profile bleiben unverändert (~/.config/kanshi/config)"
  elif command -v python3 >/dev/null; then
    python3 "$CFG/sway/scripts/displays.py" write-kanshi && ok "kanshi-Profile (~/.config/kanshi/config)"
  fi

  # Hintergrundbild: weicher Verlauf, falls noch keins vorhanden ist
  local im
  im=$(command -v magick || command -v convert || true)
  if [[ -n $im && ! -f $CFG/i3-apple/wallpapers/verlauf.png ]]; then
    "$im" -size 3840x2160 xc: \
      -sparse-color shepards '0,0 #0b1d3a 3840,0 #3a1c71 1200,2160 #12355b 3840,2160 #b4577a' \
      -blur 0x60 "$CFG/i3-apple/wallpapers/verlauf.png"
    ok "Hintergrundbild erzeugt (eigene Bilder nach ~/.config/i3-apple/wallpapers legen)"
  fi

  command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
}

# ── Sicherung ───────────────────────────────────────────────────────
# Alles im Benutzerordner, was dieser Installer verändern kann
backup_paths() {
  printf '%s\n' \
    "$CFG/sway" "$CFG/kanshi" "$CFG/i3-apple" "$CFG/autostart" \
    "$CFG/dconf/i3apple-sway" \
    "$DATA/icons/i3apple-sway-bar" "$DATA/icons/i3apple-sway-bar-fallback" \
    "$DATA/dbus-1/services/org.freedesktop.Notifications.i3-apple.service" \
    "$DATA/i3-apple/notifications-activate"
}

# Pfade relativ zu ~ (das Archiv wird nach ~ entpackt)
backup_rel_paths() {
  local p rel
  while IFS= read -r p; do
    rel=${p#"$HOME"/}
    if [[ $rel == "$p" || -z $rel ]]; then warn "Liegt nicht in ~, wird nicht gesichert: $p" >&2; continue; fi
    echo "$rel"
  done < <(backup_paths)
}

create_backup() {
  local archive="$BACKUP_DIR/$BACKUP_PREFIX-$TS.tar.gz" stage rel rc=0
  local present=() args=()
  msg "Bisherige Konfiguration sichern"
  mkdir -p "$BACKUP_DIR" "$CACHE"
  stage=$(mktemp -d "$CACHE/backup.XXXX")
  mkdir "$stage/_backup-info"
  : > "$stage/_backup-info/vorhanden.txt"
  : > "$stage/_backup-info/nicht-vorhanden.txt"

  while IFS= read -r rel; do
    if [[ -e $HOME/$rel || -L $HOME/$rel ]]; then
      present+=("$rel"); echo "$rel" >> "$stage/_backup-info/vorhanden.txt"
    else
      echo "$rel" >> "$stage/_backup-info/nicht-vorhanden.txt"
    fi
  done < <(backup_rel_paths)

  cat > "$stage/_backup-info/LIESMICH.txt" <<EOF
i3-apple (Sway) – Sicherung vom $(date '+%d.%m.%Y um %H:%M')
System: ${OS_NAME:-unbekannt}

Gesicherte Dateien und Ordner (relativ zu ~): siehe vorhanden.txt
Gab es zu diesem Zeitpunkt nicht:            siehe nicht-vorhanden.txt

Zurückspielen (ersetzt die Dateien und entfernt, was es damals nicht gab):
  sway/install.sh --restore "$archive"

Von Hand (nur einzelne Dateien, ohne Löschen):
  tar -xzf "$archive" -C ~ --exclude=_backup-info
EOF

  args=(-C "$stage" _backup-info)
  (( ${#present[@]} )) && args+=(-C "$HOME" "${present[@]}")
  # Archiv nur für dich lesbar; Exit-Code 1 = Datei hat sich beim Lesen geändert (unkritisch)
  (umask 077; tar -czf "$archive" "${args[@]}") || rc=$?
  rm -rf "$stage"
  if (( rc > 1 )); then
    rm -f "$archive"
    echo "Sicherung fehlgeschlagen – Abbruch, es wurde nichts verändert." >&2
    exit 1
  fi
  ok "Gesichert: $archive ($(du -h "$archive" | cut -f1), ${#present[@]} Einträge)"
}

restore_backup() { # restore_backup <archiv|latest>
  local archive=$1 rel answer
  if [[ $archive == latest ]]; then
    archive=$(ls -1t "$BACKUP_DIR"/"$BACKUP_PREFIX"-*.tar.gz 2>/dev/null | head -n1 || true)
    [[ -n $archive ]] || { echo "Keine Sway-Sicherung in $BACKUP_DIR gefunden." >&2; exit 1; }
  fi
  [[ -f $archive ]] || { echo "Datei nicht gefunden: $archive" >&2; exit 1; }
  local members
  members=$(tar -tzf "$archive" 2>/dev/null) || { echo "Archiv ist beschädigt: $archive" >&2; exit 1; }
  grep -qx '_backup-info/vorhanden.txt' <<<"$members" ||
    { echo "Keine i3-apple-Sicherung: $archive" >&2; exit 1; }

  # Nur Pfade akzeptieren, die dieser Installer selbst sichert
  local -A allowed=()
  while IFS= read -r rel; do allowed[$rel]=1; done < <(backup_rel_paths 2>/dev/null)
  local present=() absent=()
  while IFS= read -r rel; do
    [[ -n $rel && -n ${allowed[$rel]:-} ]] && present+=("$rel")
  done < <(tar -xzOf "$archive" _backup-info/vorhanden.txt)
  while IFS= read -r rel; do
    [[ -n $rel && -n ${allowed[$rel]:-} && ( -e $HOME/$rel || -L $HOME/$rel ) ]] && absent+=("$rel")
  done < <(tar -xzOf "$archive" _backup-info/nicht-vorhanden.txt 2>/dev/null || true)

  msg "Sicherung zurückspielen: $(basename "$archive")"
  tar -xzOf "$archive" _backup-info/LIESMICH.txt 2>/dev/null | head -n2 | sed 's/^/  /'
  echo
  (( ${#present[@]} )) && { echo "  Wird durch die Sicherung ersetzt:"; printf '    ~/%s\n' "${present[@]}"; }
  (( ${#absent[@]} ))  && { echo "  Wird entfernt (gab es damals nicht):"; printf '    ~/%s\n' "${absent[@]}"; }
  echo
  read -rp "  Fortfahren? Der jetzige Stand wird vorher ebenfalls gesichert. [j/N] " answer
  [[ $answer == [jJyY]* ]] || { echo "  Abgebrochen."; exit 0; }

  create_backup   # aktuellen Stand sichern, falls man zurück möchte

  for rel in "${present[@]}" "${absent[@]}"; do
    rm -rf -- "${HOME:?}/$rel"
  done
  (( ${#present[@]} )) && tar -xzf "$archive" -C "$HOME" -- "${present[@]}"

  ok "Wiederhergestellt. Abmelden und neu anmelden, damit alles wirkt."
  echo "  Die Sitzung „Sway (i3-apple)“ bleibt eingetragen. Entfernen:"
  echo "    sudo rm /usr/share/wayland-sessions/sway-apple.desktop /usr/local/bin/sway-apple-session"
}

# ── Ablauf ──────────────────────────────────────────────────────────
if [[ -n $RESTORE ]]; then restore_backup "$RESTORE"; exit 0; fi
if (( BACKUP_ONLY )); then create_backup; exit 0; fi
if (( DO_BACKUP )); then create_backup; else warn "Ohne Sicherung (--no-backup)"; fi

(( DO_PACKAGES )) && install_packages
(( DO_EWW ))      && build_eww
(( DO_ROFI ))     && build_rofi
# SwayFX ist Pflicht – ohne geht es nicht weiter (auch nicht mit --config-only)
if ! build_swayfx; then
  echo >&2
  echo "SwayFX ist nicht installiert – Abbruch, die Konfiguration wurde nicht übernommen." >&2
  echo "Fehlerursache steht in $SWAYFX_LOG (fehlende -dev-Pakete, Netz …)." >&2
  echo "Danach sway/install.sh erneut starten." >&2
  exit 1
fi
(( DO_THEMES ))   && install_themes
(( DO_PACKAGES )) && install_apps
(( DO_PACKAGES )) && install_zed
deploy
setup_session

# Läuft Sway bereits? Dann neu laden – ohne dass Bildschirm-Anordnung, Skalierung
# oder Auflösung verloren gehen: aktuelle Anordnung als Profil dieser Bildschirme
# merken (übersteht so auch die nächste Anmeldung), Zustand sichern, neu laden;
# services.sh stellt ihn danach wieder her.
if pgrep -x sway >/dev/null && [[ -n ${SWAYSOCK:-} ]]; then
  timeout 20 python3 "$CFG/sway/scripts/displays.py" remember >/dev/null 2>&1 || true
  "$CFG/sway/scripts/reload.sh" >/dev/null 2>&1 || true
  ok "Sway neu geladen (Bildschirm-Anordnung bleibt erhalten)"
fi

rofi_note=""
rofi_has_wayland || rofi_note="   Hinweis: rofi hat keine Wayland-Unterstützung und läuft über XWayland."
# SwayFX eben gebaut, aber die laufende Sitzung ist noch normales Sway
if [[ -n ${SWAYSOCK:-} ]] && is_swayfx && ! fx_wanted; then
  rofi_note+=$'\n'"   SwayFX ist neu: runde Ecken & Effekte nach Ab- und Anmelden."
fi

cat <<EOF

  ────────────────────────────────────────────────────────────
   Fertig!  Abmelden und am Anmeldebildschirm (unten links)
   die Sitzung „Sway (i3-apple)“ wählen. Plasma, GNOME und
   andere Sitzungen bleiben daneben unverändert.

   Super + Leertaste      Launcher (auch Super + Strg + Enter)
   Super + Enter          Terminal
   Super + Strg + K       alle Tastenkürzel
   Super + Strg + S       Einstellungen (Bildschirme, Autostart …)
   Super + P              Bildschirme anordnen & skalieren
$rofi_note
  ────────────────────────────────────────────────────────────
EOF
