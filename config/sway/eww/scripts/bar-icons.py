#!/usr/bin/env python3
# Eigenes Symbol-Theme der Menüleiste (nur Sway): ~/.local/share/icons/i3apple-sway-bar
#
# eww.scss legt die Leiste mit -gtk-icon-theme auf dieses Theme fest. Damit hängen
# ihre Symbole nicht mehr davon ab, welches Symbol-Theme GTK über gsettings/dconf
# der Sitzung bekommt – kam dort kein WhiteSur an (oder ein Theme ohne die
# GNOME-Namen, etwa das leere „Adwaita“ von KDE neon), zeigte die Leiste nur
# Platzhalter.
#
#   i3apple-sway-bar           keine eigenen Grafiken, erbt von WhiteSur-dark,
#                              WhiteSur, Adwaita, Breeze und hicolor
#   i3apple-sway-bar-fallback  steht ganz am Ende dieser Kette: Verweise für
#                              Symbole, die keines der Themes unter dem GNOME-Namen
#                              hat (battery-level-50-symbolic → battery-050 …)
#
#   bar-icons.py          Themes anlegen und Ersatz-Verweise abgleichen
#   bar-icons.py check    nur prüfen, ob jedes Symbol der Leiste auffindbar ist
# Exit-Code: 0 = alle Symbole da · 1 = es fehlen welche · 2 = GTK nicht verfügbar
import fcntl
import os
import sys

THEME = "i3apple-sway-bar"
FALLBACK = THEME + "-fallback"
ICONS = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "icons")
SUBDIR = "status"
INHERITS = ("WhiteSur-dark", "WhiteSur", "Adwaita", "breeze-dark", "breeze", FALLBACK, "hicolor")
SUFFIXES = (".symbolic.png", ".svg", ".png", ".xpm")

# Ohne „Directories“ verwirft GTK ein Theme samt seinen Inherits – daher immer
# einen (ggf. leeren) Ordner angeben. Hidden: taucht in keiner Theme-Auswahl auf.
INDEX = """[Icon Theme]
Name={name}
Comment=i3-apple: nur für die Menüleiste der Sitzung „Sway (i3-apple)“, erzeugt von bar-icons.py
Hidden=true
Inherits={inherits}
Directories={sub}

[{sub}]
Context=Status
Size=16
MinSize=1
MaxSize=512
Type=Scalable
"""

# BlueZ meldet Gerätetypen als Freedesktop-Namen, bluetooth.sh hängt -symbolic an
BLUEZ = ("audio-card", "audio-headphones", "audio-headset", "camera-photo", "camera-video",
         "computer", "input-gaming", "input-keyboard", "input-mouse", "input-tablet", "modem",
         "multimedia-player", "network-wireless", "phone", "printer", "scanner", "video-display")


def wanted():
    """Alle Symbole aus eww.yuck und den Leisten-Skripten → Ersatznamen in Reihenfolge."""
    w = {}

    def add(name, *alts):
        w[name] = list(alts)

    # Leiste
    add("view-app-grid-symbolic", "view-grid-symbolic", "view-app-grid", "view-grid",
        "view-list-icons-symbolic", "view-list-icons", "applications-all-symbolic")
    add("bluetooth-active-symbolic", "bluetooth-symbolic", "bluetooth-active", "bluetooth",
        "preferences-system-bluetooth-symbolic", "preferences-system-bluetooth", "network-bluetooth")
    add("bluetooth-disabled-symbolic", "bluetooth-disabled", "bluetooth-inactive",
        "network-bluetooth-inactive", "bluetooth-active-symbolic")

    for level, nums in (("excellent", ("100", "80")), ("good", ("75", "60")), ("ok", ("50", "40")),
                        ("weak", ("25", "20")), ("none", ("00", "0"))):
        alts = [f"network-wireless-signal-{level}"]
        for n in nums:
            alts += [f"network-wireless-connected-{n}", f"network-wireless-{n}"]
        if level == "none":
            alts += ["network-wireless-disconnected", "network-wireless-signal-weak-symbolic"]
        add(f"network-wireless-signal-{level}-symbolic", *alts, "network-wireless-symbolic", "network-wireless")
    add("network-wireless-disabled-symbolic", "network-wireless-disabled", "network-wireless-offline-symbolic",
        "network-wireless-offline", "network-wireless-off", "network-offline-symbolic", "network-offline")
    add("network-wired-symbolic", "network-wired", "network-wired-activated", "network-connect")

    for v in ("muted", "low", "medium", "high"):
        add(f"audio-volume-{v}-symbolic", f"audio-volume-{v}")
    add("audio-volume-overamplified-symbolic", "audio-volume-overamplified",
        "audio-volume-high-symbolic", "audio-volume-high")

    # Batterie in 10er-Stufen (battery.sh); Breeze: battery-050, ältere Themes: battery-good
    old = {0: "empty", 10: "caution", 20: "low", 30: "low", 40: "good", 50: "good",
           60: "good", 70: "good", 80: "full", 90: "full", 100: "full"}
    for n in range(0, 101, 10):
        add(f"battery-level-{n}-symbolic", f"battery-level-{n}", f"battery-{n:03d}-symbolic",
            f"battery-{n:03d}", f"battery-{old[n]}-symbolic", f"battery-{old[n]}")
        add(f"battery-level-{n}-charging-symbolic", f"battery-level-{n}-charging",
            f"battery-{n:03d}-charging-symbolic", f"battery-{n:03d}-charging",
            f"battery-{old[n]}-charging-symbolic", f"battery-{old[n]}-charging",
            f"battery-level-{n}-symbolic")
    add("battery-level-100-charged-symbolic", "battery-level-100-charged", "battery-full-charged-symbolic",
        "battery-full-charged", "battery-100-charging", "battery-level-100-charging-symbolic",
        "battery-level-100-symbolic")
    add("battery-missing-symbolic", "battery-missing", "battery-empty-symbolic", "battery-000")

    # Popups
    add("notifications-disabled-symbolic", "notifications-disabled", "notification-disabled-symbolic",
        "notification-disabled", "preferences-system-notifications-symbolic", "notifications-symbolic",
        "notifications")
    add("network-wireless-encrypted-symbolic", "network-wireless-encrypted", "object-locked-symbolic",
        "object-locked", "changes-prevent-symbolic", "lock")
    add("audio-input-microphone-symbolic", "audio-input-microphone", "audio-input-microphone-high-symbolic",
        "audio-input-microphone-high", "microphone-sensitivity-high-symbolic", "mic-on")
    add("microphone-sensitivity-muted-symbolic", "microphone-sensitivity-muted",
        "audio-input-microphone-muted-symbolic", "audio-input-microphone-muted", "mic-off",
        "audio-input-microphone-symbolic")
    add("audio-speakers-symbolic", "audio-speakers", "audio-card-symbolic", "audio-card",
        "audio-volume-high-symbolic")
    add("object-select-symbolic", "object-select", "emblem-ok-symbolic", "checkmark",
        "dialog-ok-apply", "dialog-ok")
    add("display-brightness-symbolic", "display-brightness", "brightness-high-symbolic", "brightness-high",
        "video-display-brightness", "weather-clear-symbolic", "weather-clear")
    add("application-x-executable-symbolic", "application-x-executable", "window-symbolic",
        "preferences-system-windows", "applications-system-symbolic", "applications-system")
    add("window-close-symbolic", "window-close", "dialog-close", "tab-close", "edit-delete-remove")
    for t in BLUEZ:
        if f"{t}-symbolic" not in w:
            add(f"{t}-symbolic", t, "bluetooth-active-symbolic")
    return w


def write_theme(name, inherits):
    d = os.path.join(ICONS, name)
    os.makedirs(os.path.join(d, SUBDIR), exist_ok=True)
    text = INDEX.format(name=name, inherits=",".join(inherits), sub=SUBDIR)
    path = os.path.join(d, "index.theme")
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return
    except OSError:
        pass
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(path + ".tmp", path)


def suffix(path):
    return next((s for s in SUFFIXES if path.endswith(s)), None)


def resolve(theme, name, fb_dir):
    """Datei, die GTK für das Symbol nimmt – ohne die eigenen Ersatz-Verweise."""
    info = theme.lookup_icon(name, 16, 0)
    path = info.get_filename() if info else None
    if not path or not os.path.isfile(path) or os.path.dirname(path).startswith(fb_dir):
        return None
    return path


def builtin(theme, name):
    """In GTK selbst enthalten (GResource unter /org/gtk/…)?"""
    info = theme.lookup_icon(name, 16, 0) if theme.has_icon(name) else None
    path = info.get_filename() if info else None
    return info is not None and (path is None or path.startswith("/org/"))


def found(theme, name):
    """Findet GTK das Symbol – samt Ersatz-Verweisen und eingebauten Symbolen?"""
    if builtin(theme, name):
        return True
    info = theme.lookup_icon(name, 16, 0)
    path = info.get_filename() if info else None
    return bool(path) and os.path.exists(path)


def main():
    check = sys.argv[1:] == ["check"]
    fb_dir = os.path.join(ICONS, FALLBACK, SUBDIR)
    names = wanted()

    if not check:
        # Zuerst die Theme-Dateien – eww.scss verweist auf das Theme, ohne
        # index.theme fände GTK gar kein Symbol mehr
        os.makedirs(ICONS, exist_ok=True)
        write_theme(THEME, INHERITS)
        write_theme(FALLBACK, ("hicolor",))
        lock = open(os.path.join(ICONS, FALLBACK, ".lock"), "w")
        fcntl.flock(lock, fcntl.LOCK_EX)   # services.sh und launch-bars.sh starten gleichzeitig
    elif not os.path.isfile(os.path.join(ICONS, THEME, "index.theme")):
        print(f"Symbol-Theme der Menüleiste fehlt ({ICONS}/{THEME}) – sway/install.sh --config-only")
        return 1

    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except (ImportError, ValueError) as e:
        print(f"Symbol-Theme der Menüleiste angelegt, Prüfung ohne GTK nicht möglich ({e})")
        return 2
    theme = Gtk.IconTheme.new()
    theme.set_custom_theme(THEME)

    if check:
        missing = [n for n in names if not found(theme, n)]
        links = sum(1 for e in os.scandir(fb_dir) if e.is_symlink()) if os.path.isdir(fb_dir) else 0
        if missing:
            print(f"Menüleiste: {len(missing)} von {len(names)} Symbolen fehlen: " + ", ".join(missing))
            return 1
        print(f"Menüleiste: alle {len(names)} Symbole vorhanden ({links} über Ersatz aus Breeze/Adwaita)")
        return 0

    # Ersatz nur für Symbole, die kein Theme der Kette hat; verweist auf die
    # Datei des ersten vorhandenen Ersatznamens
    linked, missing = {}, []
    for name, alts in names.items():
        if resolve(theme, name, fb_dir) or builtin(theme, name):
            continue
        target = next((t for t in (linked.get(a) or resolve(theme, a, fb_dir) for a in alts)
                       if t and suffix(t)), None)
        if target:
            linked[name] = target
        else:
            missing.append(name)

    # Nur ändern, was abweicht – eine laufende Leiste liest den Ordner neu ein
    want = {n + suffix(t): t for n, t in linked.items()}
    have = {e.name: os.readlink(e.path) for e in os.scandir(fb_dir) if e.is_symlink()}
    for fn, t in have.items():
        if want.get(fn) != t:
            os.unlink(os.path.join(fb_dir, fn))
    for fn, t in want.items():
        if have.get(fn) != t:
            os.symlink(t, os.path.join(fb_dir, fn))

    msg = f"Symbol-Theme der Menüleiste: {len(names) - len(missing)} von {len(names)} Symbolen"
    if linked:
        msg += f", {len(linked)} davon als Ersatz aus Breeze/Adwaita"
    if missing:
        print(msg + ". Fehlen: " + ", ".join(missing))
        return 1
    print(msg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
