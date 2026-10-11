#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════
#  i3-apple (Sway) · Bildschirme anordnen & skalieren
#
#    displays.py                 Fenster: Bildschirme mit der Maus ziehen,
#                                Skalierung, Auflösung, Bildrate, Drehung
#    displays.py quick <aktion>  extend-right | extend-left | extend-above |
#                                mirror | internal | external
#    displays.py profiles        gespeicherte Profile auflisten
#    displays.py save <name>     aktuelle Anordnung als Profil speichern
#    displays.py load <name>     Profil laden
#    displays.py restore         Profil zur angeschlossenen Hardware laden
#                                (nur wenn es vom aktuellen Zustand abweicht)
#    displays.py snapshot <datei>        Zustand vor einem Sway-Neuladen sichern
#    displays.py apply-snapshot <datei>  … und danach wiederherstellen
#    displays.py remember        aktuelle Anordnung als Profil dieser Kombination merken
#    displays.py mirror-start    internen Bildschirm auf alle anderen spiegeln (wl-mirror;
#                                für kanshi-Profile, die als „gespiegelt“ gemerkt sind)
#    displays.py write-kanshi    ~/.config/kanshi/config aus den Profilen neu schreiben
#  Sway setzt beim Neuladen alle Bildschirme zurück – reload.sh und services.sh
#  sorgen mit snapshot/apply-snapshot dafür, dass die Anordnung bleibt.
#
#  Profile liegen in ~/.config/i3-apple/display-profiles.json und werden
#  zusätzlich als ~/.config/kanshi/config geschrieben – kanshi lädt das
#  passende Profil beim Anstecken der Bildschirme automatisch.
#  Je Bildschirm-Kombination gibt es genau ein Profil.
# ═══════════════════════════════════════════════════════════════════
import hashlib
import html
import json
import math
import os
import re
import subprocess
import sys
import time
import unicodedata

HOME = os.path.expanduser("~")
CONFIG = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
# Wie alle anderen Skripte (und die Sway-Konfiguration): fest ~/.config/i3-apple.
# Nur kanshi selbst liest $XDG_CONFIG_HOME – seine Datei folgt daher CONFIG.
SETTINGS = os.path.join(HOME, ".config", "i3-apple")
STORE = os.path.join(SETTINGS, "display-profiles.json")
KANSHI = os.path.join(CONFIG, "kanshi", "config")
SELF = os.path.abspath(__file__)
USAGE = """Aufruf: displays.py [Befehl]
  (ohne)                       Fenster „Bildschirme“
  quick <aktion>               extend-right | extend-left | extend-above | mirror | internal | external
  profiles                     gespeicherte Profile auflisten
  save <name> | load <name>    Profil speichern / laden
  restore                      Profil zur angeschlossenen Hardware anwenden
  snapshot <datei>             Zustand vor dem Neuladen sichern
  apply-snapshot <datei>       … und danach wiederherstellen
  remember [--only-if-missing] aktuelle Anordnung als Profil merken
  mirror-start                 internen Bildschirm spiegeln (wl-mirror)
  write-kanshi                 kanshi-Konfiguration neu schreiben"""
KANSHI_HEADER = "# i3-apple: automatisch erzeugt"
CURRENT_WALLPAPER = os.path.join(SETTINGS, "current-wallpaper")

ROTATED = {"90", "270", "flipped-90", "flipped-270"}
ROTATIONS = [("normal", "Standard"), ("90", "90° (Hochformat)"), ("180", "180°"),
             ("270", "270° (Hochformat)"), ("flipped", "Gespiegelt"),
             ("flipped-90", "Gespiegelt, 90°"), ("flipped-180", "Gespiegelt, 180°"),
             ("flipped-270", "Gespiegelt, 270°")]
SCALE_PRESETS = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
INTERNAL_RE = re.compile(r"^(eDP|LVDS|DSI)")


# ── Hilfen ───────────────────────────────────────────────────────────
def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def notify(title, body=""):
    try:
        subprocess.Popen(["notify-send", "-a", "Bildschirme", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def fmt_scale(s):
    return f"{s:.4f}".rstrip("0").rstrip(".")


def fmt_hz(mhz):
    return f"{mhz / 1000:.2f}".rstrip("0").rstrip(".") + " Hz"


def fmt_mode(mode):
    w, h, r = mode
    return f"{w}x{h}@{r / 1000:.3f}Hz"


# ── Bildschirme ──────────────────────────────────────────────────────
class Output:
    def __init__(self, d):
        self.name = d.get("name", "")
        self.make = (d.get("make") or "").strip()
        self.model = (d.get("model") or "").strip()
        self.serial = (d.get("serial") or "").strip()
        self.active = bool(d.get("active"))
        modes = {(m["width"], m["height"], m["refresh"]) for m in d.get("modes") or []}
        # größte Auflösung zuerst, darin die höchste Bildrate
        self.modes = sorted(modes, key=lambda m: (-m[0] * m[1], -m[0], -m[2]))
        cm = d.get("current_mode")
        if self.active and cm:
            self.mode = (cm["width"], cm["height"], cm["refresh"])
            if self.mode not in modes:
                self.modes.insert(0, self.mode)
        else:
            self.mode = self.modes[0] if self.modes else (1920, 1080, 60000)
        rect = d.get("rect") or {}
        self.x, self.y = int(rect.get("x", 0)), int(rect.get("y", 0))
        scale = d.get("scale") or 1.0
        self.scale = float(scale) if self.active and scale > 0 else 1.0
        self.transform = d.get("transform") or "normal"

    def copy(self):
        o = Output.__new__(Output)
        o.__dict__.update(self.__dict__)
        o.modes = list(self.modes)
        return o

    @property
    def internal(self):
        return bool(INTERNAL_RE.match(self.name))

    def logical(self):
        """Größe im Sway-Layout (nach Drehung und Skalierung), wie wlroots rechnet."""
        w, h = self.mode[0], self.mode[1]
        if self.transform in ROTATED:
            w, h = h, w
        return int(w / self.scale), int(h / self.scale)

    def criteria(self):
        """Stabile Kennung für Profile: Hersteller/Modell/Seriennummer, sonst Anschluss."""
        if self.internal or not self.serial or self.serial.lower() in ("unknown", "0x00000000"):
            return self.name
        return f"{self.make} {self.model} {self.serial}".replace('"', "")

    def title(self):
        if self.internal:
            return "Integrierter Bildschirm"
        return f"{self.make} {self.model}".strip() or self.name

    def state(self):
        return {"criteria": self.criteria(), "name": self.name, "enabled": self.active,
                "mode": list(self.mode), "x": self.x, "y": self.y,
                "scale": round(self.scale, 4), "transform": self.transform}

    def set_state(self, s):
        self.active = bool(s.get("enabled", True))
        mode = tuple(s.get("mode") or self.mode)
        if mode in self.modes:
            self.mode = mode
        else:  # Bildrate leicht anders → gleiche Auflösung nehmen
            same = [m for m in self.modes if m[:2] == mode[:2]]
            if same:
                self.mode = min(same, key=lambda m: abs(m[2] - mode[2]))
        self.x, self.y = int(s.get("x", 0)), int(s.get("y", 0))
        self.scale = float(s.get("scale", 1.0)) or 1.0
        self.transform = s.get("transform", "normal")

    def sway_command(self):
        if not self.active:
            return f'output "{self.name}" disable'
        return (f'output "{self.name}" enable mode {fmt_mode(self.mode)} pos {self.x} {self.y} '
                f'scale {fmt_scale(self.scale)} transform {self.transform}')


def read_outputs():
    r = run(["swaymsg", "-t", "get_outputs", "-r"])
    if r.returncode != 0:
        raise SystemExit("swaymsg: " + (r.stderr.strip() or "Sway läuft nicht?"))
    outs = [Output(d) for d in json.loads(r.stdout)]
    outs.sort(key=lambda o: (not o.internal, o.name))
    return outs


def apply_outputs(outs):
    """Alle Bildschirme in einem Rutsch setzen; gibt (ok, Fehlertext) zurück."""
    if not any(o.active for o in outs):
        return False, "Mindestens ein Bildschirm muss eingeschaltet bleiben."
    cmds = [o.sway_command() for o in outs if o.active] + [o.sway_command() for o in outs if not o.active]
    r = run(["swaymsg", "-r", "--", "; ".join(cmds)])
    errors = []
    try:
        for res in json.loads(r.stdout or "[]"):
            if isinstance(res, dict) and not res.get("success", True):
                errors.append(res.get("error") or "unbekannter Fehler")
    except json.JSONDecodeError:
        pass
    if r.returncode != 0 and not errors:
        errors.append(r.stderr.strip() or "swaymsg meldete einen Fehler")
    return not errors, "; ".join(errors)


# ── Anordnung ────────────────────────────────────────────────────────
def rect(o):
    w, h = o.logical()
    return o.x, o.y, w, h


def overlaps(a, b):
    ax, ay, aw, ah = rect(a)
    bx, by, bw, bh = rect(b)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def touches(a, b):
    ax, ay, aw, ah = rect(a)
    bx, by, bw, bh = rect(b)
    if ax + aw == bx or bx + bw == ax:
        return ay < by + bh and by < ay + ah
    if ay + ah == by or by + bh == ay:
        return ax < bx + bw and bx < ax + aw
    return False


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def snap(outs, d, threshold=64):
    """d lückenlos an den nächstgelegenen Rand eines anderen Bildschirms legen.
    Liegt d fast bündig (oben/unten/mittig bzw. links/rechts/mittig), rastet es ein."""
    others = [o for o in outs if o.active and o is not d]
    if not others:
        d.x = d.y = 0
        return
    dx, dy, dw, dh = rect(d)
    cands = []
    for o in others:
        ox, oy, ow, oh = rect(o)
        for nx in (ox + ow, ox - dw):  # rechts / links daneben
            ny = clamp(dy, oy - dh + 1, oy + oh - 1)
            best = min((oy, oy + oh - dh, oy + (oh - dh) // 2), key=lambda a: abs(ny - a))
            if abs(ny - best) <= threshold:
                ny = best
            cands.append((nx, ny))
        for ny in (oy + oh, oy - dh):  # darunter / darüber
            nx = clamp(dx, ox - dw + 1, ox + ow - 1)
            best = min((ox, ox + ow - dw, ox + (ow - dw) // 2), key=lambda a: abs(nx - a))
            if abs(nx - best) <= threshold:
                nx = best
            cands.append((nx, ny))
    cands.sort(key=lambda p: math.hypot(p[0] - dx, p[1] - dy))
    for nx, ny in cands:
        d.x, d.y = nx, ny
        if not any(overlaps(d, o) for o in others):
            return
    # Notlösung: rechts neben alle anderen
    d.x = max(o.x + o.logical()[0] for o in others)
    d.y = min(o.y for o in others)


def normalize(outs):
    act = [o for o in outs if o.active]
    if not act:
        return
    mx, my = min(o.x for o in act), min(o.y for o in act)
    for o in act:
        o.x -= mx
        o.y -= my


def tidy(outs, changed):
    """Nach einer Größenänderung von `changed`: Überlappungen und Lücken auflösen."""
    act = [o for o in outs if o.active]
    if len(act) < 2:
        normalize(outs)
        return
    cx, cy = changed.x, changed.y
    for o in sorted((o for o in act if o is not changed), key=lambda o: math.hypot(o.x - cx, o.y - cy)):
        others = [p for p in act if p is not o]
        if any(overlaps(o, p) for p in others) or not any(touches(o, p) for p in others):
            snap(outs, o)
    normalize(outs)


def chain(first, rest, direction):
    first.x = first.y = 0
    prev = first
    for o in rest:
        pw, ph = prev.logical()
        w, h = o.logical()
        if direction == "right":
            o.x, o.y = prev.x + pw, prev.y
        elif direction == "left":
            o.x, o.y = prev.x - w, prev.y
        else:  # above, horizontal mittig
            o.x, o.y = prev.x + (pw - w) // 2, prev.y - h
        prev = o


# ── Profile ──────────────────────────────────────────────────────────
def load_store():
    try:
        with open(STORE) as f:
            store = json.load(f)
        if isinstance(store.get("profiles"), dict):
            return store
    except (OSError, ValueError, AttributeError):
        pass
    return {"profiles": {}}


def profile_key(states):
    return tuple(sorted(s["criteria"] for s in states))


def kanshi_name(name, used):
    s = name
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("Ä", "Ae"), ("Ö", "Oe"), ("Ü", "Ue"), ("ß", "ss")):
        s = s.replace(a, b)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = re.sub(r"[^A-Za-z0-9_.-]+", "_", s).strip("_") or "Profil"
    base, n = s, 2
    while s in used:
        s, n = f"{base}_{n}", n + 1
    used.add(s)
    return s


def kanshi_line(s):
    crit = '"' + s["criteria"].replace('"', "") + '"'
    if not s.get("enabled", True):
        return f"output {crit} disable"
    return (f"output {crit} enable mode {fmt_mode(tuple(s['mode']))} position {s['x']},{s['y']} "
            f"scale {fmt_scale(s['scale'])} transform {s['transform']}")


def write_kanshi(store):
    os.makedirs(os.path.dirname(KANSHI), exist_ok=True)
    if os.path.exists(KANSHI):
        with open(KANSHI) as f:
            first = f.readline()
        if not first.startswith(KANSHI_HEADER):  # fremde Konfiguration sichern
            os.replace(KANSHI, KANSHI + time.strftime(".bak-%Y%m%d-%H%M%S"))
    lines = [KANSHI_HEADER + " aus ~/.config/i3-apple/display-profiles.json",
             "# Ändern über Super+P → „Anordnung & Skalierung bearbeiten …“", ""]
    used = set()
    any_mirror = any(p.get("mirror") for p in store["profiles"].values())
    for name, p in store["profiles"].items():
        lines.append(f"# {name}")
        lines.append(f"profile {kanshi_name(name, used)} {{")
        lines += ["    " + kanshi_line(s) for s in p["outputs"]]
        # Spiegeln kann kanshi nicht selbst: wl-mirror starten bzw. beim Wechsel
        # in ein anderes Profil beenden (sonst läge das Spiegelfenster über dem
        # verbliebenen Bildschirm)
        if p.get("mirror"):
            lines.append(f'    exec python3 "{SELF}" mirror-start')
        elif any_mirror:
            lines.append("    exec pkill -x wl-mirror")
        lines += ["}", ""]
    tmp = KANSHI + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines))
    os.replace(tmp, KANSHI)


def reload_kanshi():
    if run(["pgrep", "-x", "kanshi"]).returncode != 0:
        return
    if run(["kanshictl", "reload"]).returncode != 0:
        run(["pkill", "-HUP", "-x", "kanshi"])


def save_store(store):
    os.makedirs(SETTINGS, exist_ok=True)
    tmp = STORE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(store, f, indent=2, ensure_ascii=False)
    os.replace(tmp, STORE)
    write_kanshi(store)
    reload_kanshi()


def upsert_profile(store, name, states, mirror=False):
    """Profil speichern. Für dieselbe Bildschirm-Kombination gibt es nur ein
    Profil: name=None aktualisiert das vorhandene (oder legt „Automatisch …“ an).
    Gehört der Name schon zu einer anderen Kombination, bleibt deren Profil
    erhalten und das neue bekommt einen Zusatz („Büro (2)“). Gibt den Namen zurück."""
    profiles = store["profiles"]
    key = profile_key(states)
    for n, p in list(profiles.items()):
        if profile_key(p["outputs"]) == key:
            if name is None:
                name = n
            elif n != name:
                del profiles[n]
    if name is None:
        name = "Automatisch " + hashlib.sha1("\n".join(key).encode()).hexdigest()[:6]
    base, i = name, 2
    while name in profiles and profile_key(profiles[name]["outputs"]) != key:
        name, i = f"{base} ({i})", i + 1
    profiles[name] = {"outputs": states}
    if mirror:
        profiles[name]["mirror"] = True
    return name


def mirroring():
    """Läuft gerade ein Spiegelfenster (wl-mirror)?"""
    return run(["pgrep", "-x", "wl-mirror"]).returncode == 0


def apply_profile(profile, outs):
    by_crit = {s["criteria"]: s for s in profile["outputs"]}
    found = 0
    for o in outs:
        s = by_crit.get(o.criteria()) or by_crit.get(o.name)
        if s:
            o.set_state(s)
            found += 1
    if not found:
        return False, "Keiner der Bildschirme aus dem Profil ist angeschlossen."
    return apply_outputs(outs)


def _key(o):
    if not o.active:
        return (False,)
    return (True, o.mode, o.x, o.y, round(o.scale, 3), o.transform)


def differs(outs, states):
    """Weicht der aktuelle Zustand von den gespeicherten Werten ab?"""
    by_crit = {s["criteria"]: s for s in states}
    for o in outs:
        s = by_crit.get(o.criteria()) or by_crit.get(o.name)
        if not s:
            continue
        t = o.copy()
        t.set_state(s)
        if _key(t) != _key(o):
            return True
    return False


def remember_current(only_if_missing=False):
    """Aktuelle Anordnung als Profil dieser Bildschirm-Kombination merken –
    damit sie Neuladen, Neuanmeldung und Neuinstallation übersteht."""
    states = [o.state() for o in read_outputs()]
    store = load_store()
    key = profile_key(states)
    if only_if_missing and any(profile_key(p["outputs"]) == key for p in store["profiles"].values()):
        return None
    # Gespiegelt bleibt gespiegelt: kanshi/restore starten wl-mirror später wieder
    name = upsert_profile(store, None, states, mirror=mirroring())
    save_store(store)
    return name


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)


# ── Spiegeln (Sway kann das nicht selbst → wl-mirror) ────────────────
def stop_mirror():
    run(["pkill", "-x", "wl-mirror"])


def start_mirror(source, targets):
    if run(["sh", "-c", "command -v wl-mirror"]).returncode != 0:
        notify("Spiegeln nicht möglich", "Dafür wird wl-mirror gebraucht – Bildschirme wurden erweitert.")
        return
    for t in targets:
        run(["swaymsg", "focus", "output", t.name])
        subprocess.Popen(["setsid", "-f", "wl-mirror", "--fullscreen", source.name],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.6)
    run(["swaymsg", "focus", "output", source.name])


def split_internal(outs):
    """(Hauptbildschirm, übrige): das Laptop-Panel, sonst der erste nach Name.
    display-menu.sh wählt nach derselben Regel."""
    internal = next((o for o in outs if o.internal), outs[0])
    return internal, [o for o in outs if o is not internal]


def mirror_now():
    """Internen Bildschirm auf alle anderen aktiven spiegeln (neu starten)."""
    outs = read_outputs()
    internal, ext = split_internal(outs)
    ext = [o for o in ext if o.active]
    stop_mirror()
    if internal.active and ext:
        start_mirror(internal, ext)


# ── Kommandozeile ────────────────────────────────────────────────────
def quick(action):
    outs = read_outputs()
    internal, ext = split_internal(outs)
    stop_mirror()
    if action in ("extend-right", "extend-left", "extend-above", "mirror"):
        for o in outs:
            o.active = True
        direction = {"extend-left": "left", "extend-above": "above"}.get(action, "right")
        chain(internal, ext, direction)
    elif action == "internal":
        internal.active, internal.x, internal.y = True, 0, 0
        for o in ext:
            o.active = False
    elif action == "external":
        if not ext:
            return 1
        internal.active = False
        for o in ext:
            o.active = True
        chain(ext[0], ext[1:], "right")
    else:
        print(f"Unbekannte Aktion: {action}", file=sys.stderr)
        return 1
    normalize(outs)
    ok, err = apply_outputs(outs)
    if not ok:
        notify("Bildschirme", err)
        return 1
    if action == "mirror":
        start_mirror(internal, ext)
    remember_current()   # Anordnung übersteht so Neuladen und Neuanmeldung
    return 0


def cli(argv):
    cmd = argv[0]
    store = load_store()
    if cmd == "quick" and len(argv) > 1:
        return quick(argv[1])
    if cmd == "profiles":
        for name in store["profiles"]:
            print(name)
        return 0
    if cmd == "save" and len(argv) > 1:
        name = upsert_profile(store, argv[1], [o.state() for o in read_outputs()])
        save_store(store)
        notify(f"Profil „{name}“ gespeichert", "Wird beim Anschließen dieser Bildschirme automatisch geladen.")
        return 0
    if cmd == "load" and len(argv) > 1:
        p = store["profiles"].get(argv[1])
        if not p:
            notify("Profil nicht gefunden", argv[1])
            return 1
        stop_mirror()
        ok, err = apply_profile(p, read_outputs())
        if not ok:
            notify("Profil konnte nicht geladen werden", err)
        elif p.get("mirror"):
            mirror_now()
        return 0 if ok else 1
    if cmd == "restore":
        # Profil zur angeschlossenen Hardware – nur anwenden, wenn es abweicht
        outs = read_outputs()
        key = tuple(sorted(o.criteria() for o in outs))
        for p in store["profiles"].values():
            if profile_key(p["outputs"]) == key:
                ok = not differs(outs, p["outputs"]) or apply_profile(p, outs)[0]
                if ok and p.get("mirror") and not mirroring():
                    mirror_now()
                return 0 if ok else 1
        return 0
    if cmd == "snapshot" and len(argv) > 1:
        # Zustand vor einem Neuladen sichern (Sway setzt Bildschirme dabei zurück;
        # ein laufendes wl-mirror übersteht das Neuladen von selbst)
        write_json(argv[1], {"time": time.time(), "outputs": [o.state() for o in read_outputs()]})
        return 0
    if cmd == "apply-snapshot" and len(argv) > 1:
        # nach dem Neuladen: gesicherten Zustand wiederherstellen (max. 10 Minuten alt).
        # Die Datei wird in jedem Fall entfernt – auch eine kaputte, sonst würde
        # sie bei jedem weiteren Neuladen erneut versucht.
        try:
            with open(argv[1]) as f:
                snap = json.load(f)
        except (OSError, ValueError):
            snap = None
        try:
            os.remove(argv[1])
        except OSError:
            pass
        if not isinstance(snap, dict) or not isinstance(snap.get("outputs"), list) \
                or time.time() - snap.get("time", 0) > 600:
            return cli(["restore"])
        outs = read_outputs()
        if not differs(outs, snap["outputs"]):
            return 0
        return 0 if apply_profile(snap, outs)[0] else 1
    if cmd == "remember":
        # aktuelle Anordnung als Profil dieser Bildschirm-Kombination merken
        # (der Name eines vorhandenen Profils bleibt; --only-if-missing: nur neu anlegen)
        remember_current(only_if_missing="--only-if-missing" in argv[1:])
        return 0
    if cmd == "mirror-start":  # aus kanshi-Profilen, die gespiegelt gemerkt sind
        mirror_now()
        return 0
    if cmd == "write-kanshi":  # für den Installer
        write_kanshi(store)
        return 0
    print(USAGE, file=sys.stderr)
    return 1


# ── Fenster ──────────────────────────────────────────────────────────
def gui():
    import fcntl

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import GLib
    GLib.set_prgname("i3apple-displays")  # Wayland-app_id für die Fensterregel in Sway
    from gi.repository import Gdk, GdkPixbuf, Gtk, Pango, PangoCairo

    runtime = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "sway-apple")
    os.makedirs(runtime, exist_ok=True)
    lock = open(os.path.join(runtime, "displays.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        # Läuft schon: vorhandenes Fenster nach vorn holen. Gibt es keins
        # (hängender Prozess ohne Fenster), diesen beenden und neu starten.
        if run(["swaymsg", '[app_id="^i3apple-displays$"] focus']).returncode == 0:
            return 0
        for pid in run(["pgrep", "-f", r"scripts/displays\.py$"]).stdout.split():
            if pid.isdigit() and int(pid) != os.getpid():
                try:
                    os.kill(int(pid), 15)
                except OSError:
                    pass
        time.sleep(0.5)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            notify("Bildschirme", "Das Fenster läuft bereits, lässt sich aber nicht anzeigen.")
            return 1

    ACCENT = (0.04, 0.52, 1.0)

    def rounded(cr, x, y, w, h, r):
        r = min(r, w / 2, h / 2)
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def esc(s):  # für Pango-Markup (GLib.markup_escape_text verlangt je nach Version die Länge)
        return html.escape(s, quote=True)

    class Canvas(Gtk.DrawingArea):
        """Bildschirme als Rechtecke mit Hintergrundbild; ziehen zum Anordnen."""

        def __init__(self, win):
            super().__init__()
            self.win = win
            self.drag = None   # (Bildschirm, Griff-x, Griff-y, Start-x, Start-y)
            self.view = None   # (Faktor, ox, oy) – bleibt beim Ziehen fest
            self.set_size_request(-1, 280)
            self.set_hexpand(True)
            self.set_vexpand(True)
            self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                            | Gdk.EventMask.POINTER_MOTION_MASK)
            self.connect("draw", self.on_draw)
            self.connect("button-press-event", self.on_press)
            self.connect("motion-notify-event", self.on_motion)
            self.connect("button-release-event", self.on_release)
            self.wall = None
            try:
                with open(CURRENT_WALLPAPER) as f:
                    self.wall = GdkPixbuf.Pixbuf.new_from_file_at_scale(f.readline().strip(), 640, 400, True)
            except Exception:
                pass

        def compute_view(self):
            W, H = self.get_allocated_width(), self.get_allocated_height()
            act = [o for o in self.win.outs if o.active]
            if not act:
                return 1.0, W / 2, H / 2
            rects = [rect(o) for o in act]
            minx = min(r[0] for r in rects)
            miny = min(r[1] for r in rects)
            bw = max(r[0] + r[2] for r in rects) - minx
            bh = max(r[1] + r[3] for r in rects) - miny
            pad = 40
            f = max(0.005, min((W - 2 * pad) / max(bw, 1), (H - 2 * pad) / max(bh, 1), 0.3))
            return f, (W - bw * f) / 2 - minx * f, (H - bh * f) / 2 - miny * f

        def screen_rect(self, o, view):
            f, ox, oy = view
            x, y, w, h = rect(o)
            return ox + x * f, oy + y * f, w * f, h * f

        def draw_order(self):
            act = [o for o in self.win.outs if o.active]
            top = self.drag[0] if self.drag else self.win.sel
            return [o for o in act if o is not top] + ([top] if top in act else [])

        def on_draw(self, _w, cr):
            W, H = self.get_allocated_width(), self.get_allocated_height()
            rounded(cr, 0, 0, W, H, 12)
            cr.set_source_rgb(0.15, 0.15, 0.17)
            cr.fill()
            view = self.view or self.compute_view()
            for o in self.draw_order():
                self.draw_output(cr, o, view)
            if not any(o.active for o in self.win.outs):
                self.text(cr, W / 2, H / 2, "Kein Bildschirm eingeschaltet", 11, False)
            return False

        def draw_output(self, cr, o, view):
            x, y, w, h = self.screen_rect(o, view)
            x, y, w, h = x + 2, y + 2, w - 4, h - 4
            dragging = self.drag and self.drag[0] is o
            cr.save()
            rounded(cr, x, y, w, h, 6)
            cr.clip()
            if self.wall is not None:
                pw, ph = self.wall.get_width(), self.wall.get_height()
                s = max(w / pw, h / ph)
                cr.save()
                cr.translate(x + (w - pw * s) / 2, y + (h - ph * s) / 2)
                cr.scale(s, s)
                Gdk.cairo_set_source_pixbuf(cr, self.wall, 0, 0)
                cr.paint()
                cr.restore()
            else:
                cr.set_source_rgb(0.12, 0.2, 0.35)
                cr.paint()
            cr.set_source_rgba(0, 0, 0, 0.30 if dragging else 0.22)
            cr.paint()
            # Menüleiste (wie in macOS' Anordnungs-Ansicht)
            cr.rectangle(x, y, w, max(3, h * 0.05))
            cr.set_source_rgba(1, 1, 1, 0.55)
            cr.fill()
            cr.restore()

            rounded(cr, x, y, w, h, 6)
            if o is self.win.sel:
                cr.set_source_rgb(*ACCENT)
                cr.set_line_width(3)
            else:
                cr.set_source_rgba(1, 1, 1, 0.35)
                cr.set_line_width(1)
            cr.stroke()

            lw, lh = o.logical()
            self.text(cr, x + w / 2, y + h / 2 - 9, o.name, 11, True)
            self.text(cr, x + w / 2, y + h / 2 + 9,
                      f"{lw} × {lh}  ·  {round(o.scale * 100)} %", 9, False)

        def text(self, cr, cx, cy, s, size, bold):
            layout = PangoCairo.create_layout(cr)
            fd = Pango.FontDescription.from_string(f"SF Pro Text, Sans {'Bold ' if bold else ''}{size}")
            layout.set_font_description(fd)
            layout.set_text(s, -1)
            tw, th = layout.get_pixel_size()
            cr.move_to(cx - tw / 2 + 1, cy - th / 2 + 1)
            cr.set_source_rgba(0, 0, 0, 0.6)
            PangoCairo.show_layout(cr, layout)
            cr.move_to(cx - tw / 2, cy - th / 2)
            cr.set_source_rgb(1, 1, 1)
            PangoCairo.show_layout(cr, layout)

        def hit(self, ev, view):
            for o in reversed(self.draw_order()):
                x, y, w, h = self.screen_rect(o, view)
                if x <= ev.x <= x + w and y <= ev.y <= y + h:
                    return o
            return None

        def set_cursor(self, name):
            win = self.get_window()
            if win is not None:
                win.set_cursor(Gdk.Cursor.new_from_name(self.get_display(), name) if name else None)

        def on_press(self, _w, ev):
            if ev.button != 1:
                return False
            view = self.compute_view()
            o = self.hit(ev, view)
            if o is None:
                return False
            self.win.select(o)
            f, ox, oy = view
            self.view = view
            self.drag = (o, (ev.x - ox) / f - o.x, (ev.y - oy) / f - o.y, o.x, o.y)
            self.set_cursor("grabbing")
            self.queue_draw()
            return True

        def on_motion(self, _w, ev):
            if not self.drag:
                self.set_cursor("grab" if self.hit(ev, self.compute_view()) else None)
                return False
            o, gx, gy, _, _ = self.drag
            f, ox, oy = self.view
            o.x = int(round((ev.x - ox) / f - gx))
            o.y = int(round((ev.y - oy) / f - gy))
            self.queue_draw()
            return True

        def on_release(self, _w, ev):
            if not self.drag:
                return False
            o, _, _, x0, y0 = self.drag
            f = self.view[0]
            self.drag = None
            self.view = None
            self.set_cursor("grab")
            if (o.x, o.y) != (x0, y0):
                snap(self.win.outs, o, threshold=24 / f)
                normalize(self.win.outs)
                self.win.changed()
            self.queue_draw()
            return True

    class Window(Gtk.Window):
        def __init__(self):
            super().__init__(title="Bildschirme")
            self.set_default_size(920, 700)
            self.set_position(Gtk.WindowPosition.CENTER)
            self.outs = []
            self.sel = None
            self.updating = False
            self.dirty = False

            hb = Gtk.HeaderBar(title="Bildschirme", subtitle="Anordnung, Auflösung und Skalierung",
                               show_close_button=True)
            self.set_titlebar(hb)
            self.btn_apply = Gtk.Button(label="Anwenden")
            self.btn_apply.get_style_context().add_class("suggested-action")
            self.btn_apply.connect("clicked", self.on_apply)
            self.btn_reset = Gtk.Button(label="Zurücksetzen")
            self.btn_reset.set_tooltip_text("Aktuelle Einstellungen neu einlesen")
            self.btn_reset.connect("clicked", lambda *_: self.reload())
            btn_profile = Gtk.Button(label="Als Profil speichern …")
            btn_profile.connect("clicked", self.on_save_profile)
            hb.pack_end(self.btn_apply)
            hb.pack_end(self.btn_reset)
            hb.pack_start(btn_profile)

            root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            for side in ("top", "bottom", "start", "end"):
                getattr(root, f"set_margin_{side}")(16)
            self.add(root)

            hint = Gtk.Label(xalign=0, wrap=True,
                             label="Ziehe die Bildschirme mit der Maus an die gewünschte Position – "
                                   "sie rasten am nächsten Rand ein. Ein Klick wählt einen Bildschirm "
                                   "zum Bearbeiten aus.")
            hint.get_style_context().add_class("dim-label")
            root.pack_start(hint, False, False, 0)

            self.canvas = Canvas(self)
            root.pack_start(self.canvas, True, True, 0)

            self.chooser = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
            root.pack_start(self.chooser, False, False, 0)

            grid = Gtk.Grid(column_spacing=18, row_spacing=10, margin_top=4)
            root.pack_start(grid, False, False, 0)

            self.title_lbl = Gtk.Label(xalign=0, use_markup=True)
            grid.attach(self.title_lbl, 0, 0, 3, 1)

            def row(r, text, widget):
                lbl = Gtk.Label(label=text, xalign=1)
                lbl.get_style_context().add_class("dim-label")
                grid.attach(lbl, 0, r, 1, 1)
                grid.attach(widget, 1, r, 2, 1)

            self.sw_active = Gtk.Switch(halign=Gtk.Align.START)
            self.sw_active.connect("notify::active", self.on_active)
            row(1, "Eingeschaltet", self.sw_active)

            # Skalierung: Stufen wie bei macOS/GNOME + feine Einstellung in %
            scale_box = Gtk.Box(spacing=10)
            presets = Gtk.Box()
            presets.get_style_context().add_class("linked")
            self.preset_btns = []
            for s in SCALE_PRESETS:
                b = Gtk.ToggleButton(label=f"{round(s * 100)} %")
                b.connect("toggled", self.on_preset, s)
                presets.pack_start(b, False, False, 0)
                self.preset_btns.append((s, b))
            self.spin = Gtk.SpinButton.new_with_range(50, 400, 5)
            self.spin.set_digits(0)
            self.spin.set_tooltip_text("Skalierung in Prozent (in 5-%-Schritten)")
            self.spin.connect("value-changed", self.on_spin)
            pct = Gtk.Label(label="%")
            self.effective = Gtk.Label(xalign=0)
            self.effective.get_style_context().add_class("dim-label")
            scale_box.pack_start(presets, False, False, 0)
            scale_box.pack_start(self.spin, False, False, 0)
            scale_box.pack_start(pct, False, False, 0)
            scale_box.pack_start(self.effective, False, False, 6)
            row(2, "Skalierung", scale_box)

            self.cb_res = Gtk.ComboBoxText()
            self.cb_res.connect("changed", self.on_res)
            row(3, "Auflösung", self.cb_res)

            self.cb_hz = Gtk.ComboBoxText()
            self.cb_hz.connect("changed", self.on_hz)
            row(4, "Bildwiederholrate", self.cb_hz)

            self.cb_rot = Gtk.ComboBoxText()
            for key, label in ROTATIONS:
                self.cb_rot.append(key, label)
            self.cb_rot.connect("changed", self.on_rot)
            row(5, "Drehung", self.cb_rot)

            self.info = Gtk.Label(xalign=0, wrap=True)
            self.info.get_style_context().add_class("dim-label")
            grid.attach(self.info, 0, 6, 3, 1)

            self.connect("key-press-event", self.on_key)
            self.connect("destroy", Gtk.main_quit)
            self.reload()

        # ── Zustand ─────────────────────────────────────────────
        def reload(self):
            name = self.sel.name if self.sel else None
            self.outs = read_outputs()
            self.sel = next((o for o in self.outs if o.name == name), None) \
                or next((o for o in self.outs if o.active), None) or (self.outs[0] if self.outs else None)
            self.dirty = False
            self.btn_apply.set_sensitive(False)
            self.rebuild_chooser()
            self.fill_panel()
            self.canvas.queue_draw()

        def changed(self, note=""):
            self.dirty = True
            self.btn_apply.set_sensitive(True)
            self.info.set_text(note)
            self.rebuild_chooser()
            self.fill_panel()
            self.canvas.queue_draw()

        def select(self, o):
            if o is not self.sel:
                self.sel = o
                self.rebuild_chooser()
                self.fill_panel()
                self.canvas.queue_draw()

        def rebuild_chooser(self):
            for c in self.chooser.get_children():
                self.chooser.remove(c)
            if len(self.outs) < 2:
                return
            for o in self.outs:
                b = Gtk.ToggleButton(label=o.name + ("" if o.active else "  (aus)"))
                b.set_tooltip_text(o.title())
                b.set_active(o is self.sel)
                b.connect("clicked", lambda _b, out=o: self.select(out))
                self.chooser.pack_start(b, False, False, 0)
            self.chooser.show_all()

        def fill_panel(self):
            o = self.sel
            self.updating = True
            try:
                if o is None:
                    self.title_lbl.set_markup("<b>Keine Bildschirme gefunden</b>")
                    return
                self.title_lbl.set_markup(
                    f"<span size='large'><b>{esc(o.title())}</b></span>   "
                    f"<span alpha='55%'>{esc(o.name)}</span>")
                self.sw_active.set_active(o.active)

                self.res_list = []
                for m in o.modes:
                    if m[:2] not in self.res_list:
                        self.res_list.append(m[:2])
                self.cb_res.remove_all()
                for i, (w, h) in enumerate(self.res_list):
                    self.cb_res.append_text(f"{w} × {h}" + ("   (nativ)" if i == 0 else ""))
                if o.mode[:2] in self.res_list:
                    self.cb_res.set_active(self.res_list.index(o.mode[:2]))
                self.fill_hz()

                self.spin.set_value(round(o.scale * 100))
                for s, b in self.preset_btns:
                    b.set_active(abs(s - o.scale) < 0.001)
                if not self.cb_rot.set_active_id(o.transform):
                    self.cb_rot.set_active_id("normal")
                lw, lh = o.logical()
                self.effective.set_text(f"wirkt wie {lw} × {lh}")

                for w in (self.spin, self.cb_res, self.cb_hz, self.cb_rot, *[b for _, b in self.preset_btns]):
                    w.set_sensitive(o.active)
            finally:
                self.updating = False

        def fill_hz(self):
            o = self.sel
            self.hz_list = [m[2] for m in o.modes if m[:2] == o.mode[:2]]
            self.cb_hz.remove_all()
            for r in self.hz_list:
                self.cb_hz.append_text(fmt_hz(r))
            if o.mode[2] in self.hz_list:
                self.cb_hz.set_active(self.hz_list.index(o.mode[2]))

        # ── Einstellungen ───────────────────────────────────────
        def on_active(self, sw, _p):
            if self.updating or self.sel is None:
                return
            o = self.sel
            on = sw.get_active()
            if not on and sum(1 for p in self.outs if p.active) <= 1:
                self.updating = True
                sw.set_active(True)
                self.updating = False
                self.info.set_text("Mindestens ein Bildschirm muss eingeschaltet bleiben.")
                return
            o.active = on
            if on:  # rechts neben die anderen legen
                others = [p for p in self.outs if p.active and p is not o]
                o.x = max((p.x + p.logical()[0] for p in others), default=0)
                o.y = min((p.y for p in others), default=0)
                normalize(self.outs)
            else:   # Lücke schließen, die der ausgeschaltete Bildschirm hinterlässt
                tidy(self.outs, o)
            self.changed()

        def set_scale(self, s):
            o = self.sel
            if o is None or abs(o.scale - s) < 0.0001:
                return
            o.scale = s
            tidy(self.outs, o)
            self.changed()

        def on_preset(self, btn, s):
            if self.updating:
                return
            if btn.get_active():
                self.set_scale(s)
            else:  # Stufe lässt sich nicht „abwählen“
                self.updating = True
                btn.set_active(abs(self.sel.scale - s) < 0.001)
                self.updating = False

        def on_spin(self, spin):
            if not self.updating:
                self.set_scale(spin.get_value() / 100)

        def on_res(self, cb):
            i = cb.get_active()
            if self.updating or i < 0:
                return
            o = self.sel
            w, h = self.res_list[i]
            rates = [m for m in o.modes if m[:2] == (w, h)]
            same = [m for m in rates if m[2] == o.mode[2]]
            o.mode = same[0] if same else max(rates, key=lambda m: m[2])
            tidy(self.outs, o)
            self.changed()

        def on_hz(self, cb):
            i = cb.get_active()
            if self.updating or i < 0:
                return
            o = self.sel
            o.mode = (o.mode[0], o.mode[1], self.hz_list[i])
            self.changed()

        def on_rot(self, cb):
            if self.updating or cb.get_active_id() is None:
                return
            self.sel.transform = cb.get_active_id()
            tidy(self.outs, self.sel)
            self.changed()

        def on_key(self, _w, ev):
            if ev.keyval == Gdk.KEY_Escape:
                self.destroy()
                return True
            return False

        # ── Anwenden ────────────────────────────────────────────
        def message(self, kind, text, secondary=""):
            dlg = Gtk.MessageDialog(transient_for=self, modal=True, message_type=kind,
                                    buttons=Gtk.ButtonsType.OK, text=text)
            if secondary:
                dlg.format_secondary_text(secondary)
            dlg.run()
            dlg.destroy()

        def on_apply(self, *_):
            stop_mirror()
            before = read_outputs()
            ok, err = apply_outputs(self.outs)
            if not ok:
                self.message(Gtk.MessageType.ERROR, "Einstellungen konnten nicht übernommen werden", err)
                apply_outputs(before)
                self.reload()
                return
            if self.ask_keep():
                store = load_store()
                name = upsert_profile(store, None, [o.state() for o in read_outputs()])
                save_store(store)
                notify("Anordnung gespeichert",
                       f"Profil „{name}“ – wird beim Anschließen dieser Bildschirme automatisch geladen.")
            else:
                apply_outputs(before)
            self.reload()

        def ask_keep(self, seconds=15):
            dlg = Gtk.MessageDialog(transient_for=self, modal=True,
                                    message_type=Gtk.MessageType.QUESTION,
                                    buttons=Gtk.ButtonsType.NONE,
                                    text="Bildschirmeinstellungen beibehalten?")
            dlg.add_buttons("Zurücksetzen", Gtk.ResponseType.REJECT,
                            "Beibehalten", Gtk.ResponseType.ACCEPT)
            dlg.set_default_response(Gtk.ResponseType.ACCEPT)
            left = [seconds]

            def text():
                dlg.format_secondary_text(
                    f"Ohne Bestätigung werden die vorherigen Einstellungen in {left[0]} Sekunden wiederhergestellt.")

            def tick():
                left[0] -= 1
                if left[0] <= 0:
                    dlg.response(Gtk.ResponseType.REJECT)
                    return False
                text()
                return True

            text()
            source = GLib.timeout_add_seconds(1, tick)
            resp = dlg.run()
            if left[0] > 0:
                GLib.source_remove(source)
            dlg.destroy()
            return resp == Gtk.ResponseType.ACCEPT

        def on_save_profile(self, *_):
            dlg = Gtk.Dialog(title="Als Profil speichern", transient_for=self, modal=True)
            dlg.add_buttons("Abbrechen", Gtk.ResponseType.CANCEL, "Speichern", Gtk.ResponseType.OK)
            dlg.set_default_response(Gtk.ResponseType.OK)
            box = dlg.get_content_area()
            box.set_spacing(8)
            for side in ("top", "bottom", "start", "end"):
                getattr(box, f"set_margin_{side}")(12)
            box.add(Gtk.Label(xalign=0, label="Name für diese Anordnung (z. B. Büro, Zuhause):"))
            entry = Gtk.Entry(activates_default=True)
            box.add(entry)
            note = Gtk.Label(xalign=0, wrap=True, max_width_chars=50,
                             label="Gespeichert wird die Anordnung, wie sie hier zu sehen ist. "
                                   "Sie wird automatisch geladen, sobald genau diese Bildschirme "
                                   "angeschlossen sind.")
            note.get_style_context().add_class("dim-label")
            box.add(note)
            dlg.show_all()
            resp = dlg.run()
            name = entry.get_text().strip()
            dlg.destroy()
            if resp != Gtk.ResponseType.OK or not name:
                return
            store = load_store()
            name = upsert_profile(store, name, [o.state() for o in self.outs])
            save_store(store)
            notify(f"Profil „{name}“ gespeichert",
                   "Wird beim Anschließen dieser Bildschirme automatisch geladen.")

    win = Window()
    win.show_all()
    Gtk.main()
    return 0


def gui_safe():
    """Fenster starten; jeder Fehler landet als Mitteilung und im Protokoll,
    statt dass einfach nichts passiert."""
    log = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "sway-apple", "displays.log")
    try:
        return gui()
    except Exception as e:  # noqa: BLE001
        import traceback
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "w") as f:
            traceback.print_exc(file=f)
        traceback.print_exc()
        notify("Bildschirme: Fenster konnte nicht geöffnet werden",
               f"{type(e).__name__}: {e}\nDetails: {log}")
        return 1


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(cli(sys.argv[1:]))
    sys.exit(gui_safe())
