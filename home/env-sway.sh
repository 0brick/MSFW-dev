# i3-apple: Umgebung für die Sway-Sitzung „Sway (i3-apple)“.
# Wird von /usr/local/bin/sway-apple-session vor dem Start von Sway geladen
# (POSIX-sh). Alles hier gilt nur für diese Sitzung – Plasma, GNOME und andere
# Sitzungen sehen nichts davon.

export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export XCURSOR_THEME=macOS
export XCURSOR_SIZE=24

# Eigene dconf-Datenbank (~/.config/dconf/i3apple-sway): GTK-Theme, Symbole,
# Schrift und Hell/Dunkel der Sway-Sitzung ändern nie die Werte von GNOME/Plasma
export DCONF_PROFILE="$HOME/.config/i3-apple/dconf-profile"

# Eigene Konfiguration für kitty – ~/.config/kitty bleibt für andere Desktops
export KITTY_CONFIG_DIRECTORY="$HOME/.config/sway/kitty"

# Apps nativ unter Wayland (sonst über XWayland)
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM="wayland;xcb"
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export ELECTRON_OZONE_PLATFORM_HINT=auto
export _JAVA_AWT_WM_NONREPARENTING=1

if [ -e /etc/xdg/menus/plasma-applications.menu ] || command -v plasmashell >/dev/null 2>&1; then
  # KDE (z. B. KDE neon): Qt- und KDE-Apps nutzen die KDE-Einstellungen (nur lesend),
  # Dolphin & Co. finden über das Plasma-Menü ihre „Öffnen mit“-Liste
  export QT_QPA_PLATFORMTHEME=kde
  export XDG_MENU_PREFIX=plasma-
else
  export QT_QPA_PLATFORMTHEME=gtk3
fi

# PATH: ~/.config/sway/bin (rofi mit Sway-Design) und ~/.local/bin (eww)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH="$HOME/.config/sway/bin:$PATH"

# Selbst gebautes SwayFX (sway/install.sh → build_swayfx) hat Vorrang vor dem
# System-Sway – sway-apple-session startet danach einfach „sway“. Nur wenn es
# noch startet: Nach einem System-Update kann die wlroots-Bibliothek fehlen,
# dann läuft die Sitzung mit dem normalen Sway weiter (ohne Effekte).
_swayfx="$HOME/.local/share/i3-apple/swayfx/bin"
if [ -x "$_swayfx/sway" ] && "$_swayfx/sway" --version >/dev/null 2>&1; then
  case ":$PATH:" in
    *":$_swayfx:"*) ;;
    *) export PATH="$_swayfx:$PATH" ;;
  esac
  # Kam libxkbcommon als Unterprojekt mit (System-Version zu alt), sucht es
  # Tastaturlayouts und Compose-Tabellen sonst in seinem eigenen Ordner
  if [ -e "$_swayfx/../lib/libxkbcommon.so.0" ]; then
    [ -d /usr/share/X11/xkb ] && export XKB_CONFIG_ROOT=/usr/share/X11/xkb
    [ -d /usr/share/X11/locale ] && export XLOCALEDIR=/usr/share/X11/locale
  fi
fi
unset _swayfx

# Effekte (Unschärfe, Schatten, runde Ecken) gibt es nur mit SwayFX –
# normales Sway bekommt eine leere fx.conf (unbekannte Befehle wären Fehler).
# Erkennung an der Versionszeile, sonst am Programm selbst: Manche Pakete
# melden sich als „sway version …“, nur SwayFX kennt aber corner_radius.
_fx="$HOME/.config/sway/fx.conf"
_sway=$(command -v sway 2>/dev/null)
if [ -n "$_sway" ] && [ -f "$HOME/.config/sway/fx-effects.conf" ] &&
   { "$_sway" --version 2>/dev/null | grep -qi swayfx || grep -qa corner_radius "$_sway"; }; then
  cp "$HOME/.config/sway/fx-effects.conf" "$_fx"
  # Animationen (Fenster, Arbeitsflächen) gibt es erst ab SwayFX 0.6
  if [ -f "$HOME/.config/sway/fx-animations.conf" ] && grep -qa animation_duration_ms "$_sway"; then
    cat "$HOME/.config/sway/fx-animations.conf" >> "$_fx"
  fi
else
  : > "$_fx"
fi
unset _fx _sway
