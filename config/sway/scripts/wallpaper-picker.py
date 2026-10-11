#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════
#  i3-apple (Sway) · Hintergrundbild wählen (⌘⌃W)
#
#  Aufbau wie in den macOS-Systemeinstellungen:
#  • Seitenleiste: „Alle Bilder“, die Hintergrund-Ordner, Bilder und der
#    persönliche Ordner; „Ordner hinzufügen …“ merkt sich weitere Ordner.
#  • Rechts ein Raster mit Vorschaubildern. Ordner erscheinen als Kacheln
#    (mit dem ersten Bild als Vorschau) und öffnen sich per Klick;
#    ‹ bzw. Alt+← geht zurück, Alt+↑ in den übergeordneten Ordner.
#  • Ein Klick auf ein Bild übernimmt es und schließt das Fenster.
#  • Das Suchfeld filtert den aktuellen Ordner (auch Wortteile und unscharf).
#    Beginnt die Eingabe mit /, ~ oder ., gilt sie als Pfad: Vorschläge
#    klappen auf, Tab vervollständigt wie im Terminal, Enter öffnet.
#  • Esc leert erst das Suchfeld, dann schließt es das Fenster.
#  Ordner, aus denen ein Bild gewählt wurde, merkt sich wallpaper.sh –
#  sie erscheinen danach in der Seitenleiste und bei „zufällig“.
# ═══════════════════════════════════════════════════════════════════
import fcntl
import hashlib
import math
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GLib  # noqa: E402

GLib.set_prgname("i3apple-wallpaper")  # Wayland-app_id für die Fensterregel in Sway

from gi.repository import Gdk, GdkPixbuf, Gtk, Pango  # noqa: E402

HOME = os.path.expanduser("~")
REAL_HOME = os.path.realpath(HOME)   # Orte werden als realpath verglichen
SCRIPTS = os.path.dirname(os.path.realpath(__file__))
WALLPAPER_SH = os.path.join(SCRIPTS, "wallpaper.sh")
SETTINGS = os.path.join(HOME, ".config", "i3-apple")
CURRENT = os.path.join(SETTINGS, "current-wallpaper")
BUNDLED = os.path.join(SETTINGS, "wallpapers")
RUNTIME = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "sway-apple")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "i3-apple", "thumbs")
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
THUMB_W, THUMB_H = 184, 115
RADIUS = 10           # Ecken der Vorschaubilder
FADE_US = 220_000     # Einblenden eines fertigen Vorschaubilds (µs)
SLIDE_MS = 220        # Wechsel zwischen Ordnern
MAX_ITEMS = 400
LIBRARY = None        # Ort „Alle Bilder“ (sonst ist ein Ort ein Ordnerpfad)

# Nur innerhalb des Fensters (.panel) – der Dialog „Ordner hinzufügen“
# behält das normale GTK-Design. border-radius des Panels = corner_radius
# in fx-effects.conf, sonst schimmert die Unschärfe in den Ecken durch.
CSS = b"""
window.picker { background-color: transparent; }
.panel {
  background-color: rgba(30, 30, 34, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 12px;
  color: #f5f5f7;
  font-family: "SF Pro Text", sans-serif;
}
.panel scrolledwindow, .panel viewport, .panel flowbox, .panel list,
.panel stack { background-color: transparent; }

.sidebar {
  background-color: rgba(255, 255, 255, 0.04);
  border-right: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px 0 0 12px;
  padding: 16px 10px 10px 10px;
}
.sidebar-head { font-size: 15px; font-weight: 700; padding: 0 10px 6px 10px; }
.sidebar-title {
  color: rgba(245, 245, 247, 0.45);
  font-size: 11px;
  font-weight: 700;
  padding: 14px 10px 4px 10px;
}
.sidebar row {
  padding: 6px 10px;
  margin: 1px 0;
  border-radius: 7px;
  color: rgba(245, 245, 247, 0.92);
  transition: background-color 150ms ease;
}
.sidebar row:hover { background-color: rgba(255, 255, 255, 0.06); }
.sidebar row:selected { background-color: rgba(255, 255, 255, 0.14); color: #ffffff; }
.sidebar row image { color: #0a84ff; }
.sidebar row.heading, .sidebar row.heading:hover { background-color: transparent; padding: 0; }

button.flat-btn {
  all: unset;
  padding: 6px 10px;
  border-radius: 7px;
  color: rgba(245, 245, 247, 0.80);
  transition: background-color 150ms ease, opacity 150ms ease;
}
button.flat-btn:hover { background-color: rgba(255, 255, 255, 0.08); color: #ffffff; }
button.flat-btn:active { background-color: rgba(255, 255, 255, 0.14); }
button.flat-btn:disabled { opacity: 0.3; }
button.nav-btn { padding: 0; min-width: 30px; min-height: 30px; }

.toolbar { padding: 14px 16px 10px 12px; }
.title { font-size: 15px; font-weight: 700; }
.subtitle { font-size: 11px; color: rgba(245, 245, 247, 0.55); }

entry.query {
  all: unset;
  min-height: 30px;
  min-width: 240px;
  padding: 0 8px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.10);
  background-color: rgba(255, 255, 255, 0.07);
  color: #f5f5f7;
  caret-color: #0a84ff;
  font-size: 13px;
  transition: border-color 150ms ease, background-color 150ms ease, box-shadow 150ms ease;
}
entry.query:focus {
  border-color: rgba(10, 132, 255, 0.85);
  background-color: rgba(255, 255, 255, 0.10);
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.28);
}
entry.query image { color: rgba(245, 245, 247, 0.55); padding: 0 4px; }
entry.query selection { background-color: rgba(10, 132, 255, 0.45); color: #ffffff; }

.grid { padding: 4px 12px 14px 12px; }
.grid flowboxchild {
  padding: 8px;
  border-radius: 12px;
  transition: background-color 160ms ease;
}
.grid flowboxchild:hover { background-color: rgba(255, 255, 255, 0.06); }
.grid flowboxchild:selected { background-color: rgba(255, 255, 255, 0.12); }
.thumb-label { font-size: 12px; color: rgba(245, 245, 247, 0.90); }
.thumb-meta { font-size: 11px; color: rgba(245, 245, 247, 0.50); }
.folder-icon { color: #64d2ff; }
.folder-badge {
  background-color: rgba(0, 0, 0, 0.55);
  border-radius: 7px;
  padding: 4px;
}
.folder-badge image { color: #64d2ff; }
.empty { color: rgba(245, 245, 247, 0.55); padding: 60px; }

.footer {
  padding: 8px 16px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  font-size: 11px;
  color: rgba(245, 245, 247, 0.45);
}
"""


# ── Pfade ────────────────────────────────────────────────────────────
def is_path_query(text):
    return text.startswith(("/", "~", "./", "../")) or text in (".", "..")


def expand(text):
    path = os.path.expanduser(text)
    return path if os.path.isabs(path) else os.path.join(HOME, path)


def split_query(text):
    """'~/Bil' → ('~/', 'Bil'), '~' → ('~/', '')"""
    if text in ("~", ".", ".."):
        text += "/"
    i = text.rfind("/")
    return text[: i + 1], text[i + 1:]


def tilde(path):
    if path == HOME or path.startswith(HOME + "/"):
        return "~" + path[len(HOME):]
    return path


def is_image(name):
    return name.lower().endswith(IMAGE_EXT)


def pictures_dir():
    pics = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)
    if not pics or os.path.realpath(pics) == os.path.realpath(HOME):
        pics = os.path.join(HOME, "Pictures")
    return os.path.realpath(pics)


_listing = {}


def listing(directory):
    """(Ordner, Bilder) eines Verzeichnisses, alphabetisch – zwischengespeichert,
    bis sich der Ordner ändert (neue oder gelöschte Dateien ändern seine mtime).
    Läuft auch in den Hintergrund-Threads (Ordner-Vorschau)."""
    try:
        mtime = os.stat(directory).st_mtime_ns
    except OSError:
        mtime = None
    hit = _listing.get(directory)
    if hit and hit[0] == mtime:
        return hit[1]
    dirs, imgs = [], []
    try:
        with os.scandir(directory) as it:
            for e in it:
                try:
                    if e.is_dir():
                        dirs.append(e.name)
                    elif e.is_file() and is_image(e.name):
                        imgs.append(e.name)
                except OSError:
                    pass
    except OSError:
        pass
    result = (sorted(dirs, key=str.casefold), sorted(imgs, key=str.casefold))
    _listing[directory] = (mtime, result)
    return result


def visible(names, base):
    """Namen, die mit base beginnen (versteckte nur, wenn base mit . beginnt)."""
    b = base.casefold()
    hidden = base.startswith(".")
    return [n for n in names if (hidden or not n.startswith(".")) and n.casefold().startswith(b)]


def score(query, text):
    """Trefferqualität (höher = besser) oder None. Jedes Wort muss passen."""
    t = text.casefold()
    total = 0
    for word in query.casefold().split():
        i = t.find(word)
        if i >= 0:
            total += 100 - min(i, 50)
            continue
        pos = 0  # unscharf: alle Buchstaben in dieser Reihenfolge
        for ch in word:
            pos = t.find(ch, pos)
            if pos < 0:
                return None
            pos += 1
        total += 10
    return total


def ranked(query, entries, key):
    """entries nach Trefferqualität sortiert; ohne Suchtext unverändert."""
    if not query.strip():
        return list(entries)
    scored = []
    for e in entries:
        s = score(query, key(e))
        if s is not None:
            scored.append((-s, key(e).casefold(), e))
    return [e for _, _, e in sorted(scored, key=lambda t: (t[0], t[1]))]


def run_wallpaper_sh(*args):
    try:
        return subprocess.run([WALLPAPER_SH, *args], capture_output=True, text=True, timeout=15).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def library():
    return [line for line in run_wallpaper_sh("list").splitlines() if line]


def wallpaper_dirs():
    return [line for line in run_wallpaper_sh("dirs").splitlines() if line]


def count_text(n_imgs, n_dirs):
    parts = []
    if n_imgs:
        parts.append(f"{n_imgs} {'Bild' if n_imgs == 1 else 'Bilder'}")
    if n_dirs:
        parts.append(f"{n_dirs} Ordner")
    return " · ".join(parts) or "Leer"


# ── Vorschaubilder ───────────────────────────────────────────────────
def load_thumb(path, w, h):
    """Vorschau in genau w×h Pixeln, mittig zugeschnitten (mit Cache)."""
    try:
        st = os.stat(path)
        key = hashlib.sha1(f"{path}\0{st.st_mtime_ns}\0{st.st_size}\0{w}x{h}".encode()).hexdigest()
        cache = os.path.join(CACHE, key + ".png")
        if os.path.exists(cache):
            try:
                os.utime(cache)   # benutzt → bleibt beim Aufräumen (prune_thumbs) erhalten
            except OSError:
                pass
            return GdkPixbuf.Pixbuf.new_from_file(cache)
        fmt, iw, ih = GdkPixbuf.Pixbuf.get_file_info(path)
        if fmt is None or iw <= 0 or ih <= 0:
            return None
        s = max(w / iw, h / ih)
        sw, sh = max(w, round(iw * s)), max(h, round(ih * s))
        pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, sw, sh, False)
        pb = pb.new_subpixbuf((pb.get_width() - w) // 2, (pb.get_height() - h) // 2, w, h).copy()
        os.makedirs(CACHE, exist_ok=True)
        tmp = f"{cache}.{threading.get_ident()}.tmp"
        pb.savev(tmp, "png", [], [])
        os.replace(tmp, cache)
        return pb
    except Exception:  # defekte Bilder, fehlende Lader, volle Platte …
        return None


def folder_info(directory, w, h):
    """(Anzahl Bilder, Anzahl Unterordner, Vorschau) für eine Ordner-Kachel.
    Vorschau ist das erste Bild – liegt keins direkt darin, das erste eines
    der ersten Unterordner (z. B. „Hintergründe/Natur“)."""
    dirs, imgs = listing(directory)
    dirs = [d for d in dirs if not d.startswith(".")]
    imgs = [i for i in imgs if not i.startswith(".")]
    first = os.path.join(directory, imgs[0]) if imgs else None
    if first is None:
        for d in dirs[:8]:
            sub_imgs = [i for i in listing(os.path.join(directory, d))[1] if not i.startswith(".")]
            if sub_imgs:
                first = os.path.join(directory, d, sub_imgs[0])
                break
    preview = load_thumb(first, w, h) if first else None
    return len(imgs), len(dirs), preview


def prune_thumbs(days=90):
    """Vorschaubilder entfernen, die seit `days` Tagen nicht mehr gebraucht wurden
    (gelöschte oder geänderte Bilder hinterlassen sonst für immer ihre Vorschau)."""
    limit = time.time() - days * 86400
    try:
        with os.scandir(CACHE) as it:
            for e in it:
                try:
                    if e.name.endswith(".png") and e.stat().st_mtime < limit:
                        os.remove(e.path)
                except OSError:
                    pass
    except OSError:
        pass


def rounded(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


class Thumb(Gtk.DrawingArea):
    """Abgerundetes Vorschaubild. Fertig geladene Bilder blenden weich ein;
    das aktuelle Hintergrundbild bekommt einen blauen Ring."""

    def __init__(self, current=False):
        super().__init__()
        self.pixbuf = None
        self.alpha = 1.0
        self.fade_start = None
        self.current = current
        self.set_size_request(THUMB_W, THUMB_H)
        self.connect("draw", self._draw)

    def set_pixbuf(self, pb, fade=False):
        if pb is None:
            return
        self.pixbuf = pb
        if fade:
            self.alpha, self.fade_start = 0.0, None
            self.add_tick_callback(self._tick)
        else:
            self.alpha = 1.0
        self.queue_draw()

    def _tick(self, _widget, clock):
        now = clock.get_frame_time()
        if self.fade_start is None:
            self.fade_start = now
        p = min(1.0, (now - self.fade_start) / FADE_US)
        self.alpha = 1 - (1 - p) ** 3   # weich auslaufend
        self.queue_draw()
        return p < 1.0

    def _draw(self, _widget, cr):
        w, h = self.get_allocated_width(), self.get_allocated_height()
        cr.save()
        rounded(cr, 0, 0, w, h, RADIUS)
        cr.clip()
        cr.set_source_rgba(1, 1, 1, 0.07)
        cr.paint()
        if self.pixbuf is not None:
            cr.scale(w / self.pixbuf.get_width(), h / self.pixbuf.get_height())
            Gdk.cairo_set_source_pixbuf(cr, self.pixbuf, 0, 0)
            cr.paint_with_alpha(self.alpha)
        cr.restore()
        if self.current:
            rounded(cr, 1.5, 1.5, w - 3, h - 3, RADIUS - 1.5)
            cr.set_source_rgba(10 / 255, 132 / 255, 1, 1)
            cr.set_line_width(3)
            cr.stroke()
        return False


class Page(Gtk.ScrolledWindow):
    """Eine Rasterseite. Zwei davon wechseln sich im Stack ab, damit der
    Übergang zwischen Ordnern gleiten kann."""

    def __init__(self, page_id, on_activate):
        super().__init__(vexpand=True, hexpand=True)
        self.page_id = page_id
        self.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.flow = Gtk.FlowBox(
            homogeneous=True, valign=Gtk.Align.START,
            selection_mode=Gtk.SelectionMode.SINGLE,
            activate_on_single_click=True,
            min_children_per_line=3, max_children_per_line=8,
            row_spacing=6, column_spacing=6)
        self.flow.get_style_context().add_class("grid")
        self.flow.connect("child-activated", lambda _f, child: on_activate(*child.item))
        self.empty = Gtk.Label(label="Keine Bilder gefunden")
        self.empty.get_style_context().add_class("empty")
        self.empty.set_no_show_all(True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.pack_start(self.flow, False, False, 0)
        content.pack_start(self.empty, False, False, 0)
        self.add(content)


# ── Fenster ──────────────────────────────────────────────────────────
class Picker(Gtk.Window):
    def __init__(self):
        super().__init__(title="Hintergrundbild")
        self.set_decorated(False)
        self.set_default_size(1060, 680)
        self.set_position(Gtk.WindowPosition.CENTER)
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)
            self.set_app_paintable(True)
        self.get_style_context().add_class("picker")

        try:
            with open(CURRENT) as f:
                self.current = f.readline().strip()
        except OSError:
            self.current = ""
        self.library = library()
        self.pool = ThreadPoolExecutor(max_workers=4)
        self.jobs = {}         # Schlüssel → laufender Hintergrund-Auftrag
        self.waiting = {}      # Schlüssel → Rückrufe, die auf das Ergebnis warten
        self.results = {}      # Schlüssel → fertiges Ergebnis (Vorschau, Ordner-Info)
        self.refresh_id = 0
        self.completion_key = None
        self.location = LIBRARY
        self.history = []
        self.place_rows = {}   # Ort → Zeile der Seitenleiste

        panel = Gtk.Box()
        panel.get_style_context().add_class("panel")
        self.add(panel)

        # ── Seitenleiste ──
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        side.set_size_request(220, -1)
        side.get_style_context().add_class("sidebar")
        head = Gtk.Label(label="Hintergrundbild", xalign=0)
        head.get_style_context().add_class("sidebar-head")
        side.pack_start(head, False, False, 0)
        self.places = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
        self.places.connect("row-activated", self.on_place)
        side_scroll = Gtk.ScrolledWindow(vexpand=True)
        side_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        side_scroll.add(self.places)
        side.pack_start(side_scroll, True, True, 0)
        add = self.flat_button("list-add-symbolic", "Ordner hinzufügen …")
        add.connect("clicked", self.on_add_folder)
        side.pack_end(add, False, False, 0)
        panel.pack_start(side, False, False, 0)

        # ── Inhalt: Werkzeugleiste, Raster, Fußzeile ──
        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
        panel.pack_start(main, True, True, 0)

        bar = Gtk.Box(spacing=10)
        bar.get_style_context().add_class("toolbar")
        self.back = self.flat_button("go-previous-symbolic")
        self.back.get_style_context().add_class("nav-btn")
        self.back.set_tooltip_text("Zurück (Alt+←)")
        self.back.set_valign(Gtk.Align.CENTER)
        self.back.connect("clicked", lambda _b: self.go_back())
        bar.pack_start(self.back, False, False, 0)
        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        self.title = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.MIDDLE)
        self.title.get_style_context().add_class("title")
        self.subtitle = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.subtitle.get_style_context().add_class("subtitle")
        heading.pack_start(self.title, False, False, 0)
        heading.pack_start(self.subtitle, False, False, 0)
        bar.pack_start(heading, True, True, 0)
        self.entry = Gtk.Entry(valign=Gtk.Align.CENTER)
        self.entry.set_placeholder_text("Suchen oder Pfad (~/…)")
        self.entry.get_style_context().add_class("query")
        self.entry.set_icon_from_icon_name(Gtk.EntryIconPosition.PRIMARY, "system-search-symbolic")
        self.entry.connect("icon-press", self.on_entry_icon)
        bar.pack_end(self.entry, False, False, 0)
        main.pack_start(bar, False, False, 0)

        self.stack = Gtk.Stack(transition_duration=SLIDE_MS, vexpand=True)
        self.pages = [Page("a", self.activate_item), Page("b", self.activate_item)]
        for p in self.pages:
            self.stack.add_named(p, p.page_id)
        self.page = self.pages[0]
        main.pack_start(self.stack, True, True, 0)

        self.message = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END)
        self.message.get_style_context().add_class("footer")
        main.pack_start(self.message, False, False, 0)

        # Autovervollständigung im Pfadmodus: Vorschläge unter dem Suchfeld +
        # Ergänzung im Feld. Der eigene changed-Handler hängt vor der
        # Vervollständigung, damit die Vorschlagsliste zum Ordner passt.
        self.store = Gtk.ListStore(str)
        self.completion = Gtk.EntryCompletion(model=self.store, text_column=0)
        self.completion.set_inline_completion(True)
        self.completion.set_inline_selection(True)
        self.completion.set_popup_completion(True)
        self.completion.set_popup_single_match(False)
        self.completion.set_minimum_key_length(1)
        self.changed_id = self.entry.connect("changed", self.on_changed)
        self.entry.set_completion(self.completion)
        self.completion.connect("match-selected", self.on_match_selected)

        self.entry.connect("activate", self.on_activate)
        self.entry.connect("key-press-event", self.on_entry_key)
        self.connect("key-press-event", self.on_key)
        self.connect("destroy", self.on_destroy)

        self.fill_places()

    @property
    def flow(self):
        """Raster der sichtbaren Seite."""
        return self.page.flow

    @staticmethod
    def flat_button(icon, text=None):
        btn = Gtk.Button()
        btn.get_style_context().add_class("flat-btn")
        img = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON)
        if text is None:
            btn.add(img)
        else:
            box = Gtk.Box(spacing=8)
            box.pack_start(img, False, False, 0)
            box.pack_start(Gtk.Label(label=text, xalign=0), False, False, 0)
            btn.add(box)
        return btn

    # ── Seitenleiste ────────────────────────────────────────────────
    def place_name(self, path):
        if path is LIBRARY:
            return "Alle Bilder"
        if path == REAL_HOME:
            return "Persönlicher Ordner"
        if path == os.path.realpath(BUNDLED):
            return "Mitgeliefert"
        return os.path.basename(path.rstrip("/")) or path

    def fill_places(self):
        for row in self.places.get_children():
            self.places.remove(row)
        self.place_rows = {}
        pics = pictures_dir()
        dirs = wallpaper_dirs()

        def heading(text):
            row = Gtk.ListBoxRow(selectable=False, activatable=False)
            row.get_style_context().add_class("heading")
            label = Gtk.Label(label=text, xalign=0)
            label.get_style_context().add_class("sidebar-title")
            row.add(label)
            self.places.add(row)

        def place(icon, path):
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=10)
            box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU), False, False, 0)
            box.pack_start(Gtk.Label(label=self.place_name(path), xalign=0,
                                     ellipsize=Pango.EllipsizeMode.END), True, True, 0)
            row.add(box)
            row.location = path
            if path is not LIBRARY:
                row.set_tooltip_text(tilde(path))
            self.places.add(row)
            self.place_rows[path] = row

        heading("BIBLIOTHEK")
        place("image-x-generic-symbolic", LIBRARY)
        if dirs:
            heading("HINTERGRUND-ORDNER")
            for d in dirs:
                inside = d == pics or d.startswith(pics + "/")
                place("folder-pictures-symbolic" if inside else "folder-symbolic", d)
        heading("ORTE")
        for icon, path in (("folder-pictures-symbolic", pics), ("user-home-symbolic", REAL_HOME)):
            if path not in self.place_rows and os.path.isdir(path):
                place(icon, path)
        self.places.show_all()
        self.sync_places()

    def sync_places(self):
        row = self.place_rows.get(self.location)
        if row is not None:
            self.places.select_row(row)
        else:
            self.places.unselect_all()

    def on_place(self, _list, row):
        location = getattr(row, "location", False)
        if location is not False:
            self.navigate(location, Gtk.StackTransitionType.CROSSFADE)

    def on_add_folder(self, _btn):
        dialog = Gtk.FileChooserDialog(title="Ordner mit Hintergrundbildern hinzufügen", transient_for=self,
                                       action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons("Abbrechen", Gtk.ResponseType.CANCEL, "Hinzufügen", Gtk.ResponseType.ACCEPT)
        dialog.set_default_response(Gtk.ResponseType.ACCEPT)
        start = self.location if self.location is not LIBRARY else pictures_dir()
        if os.path.isdir(start):
            dialog.set_current_folder(start)
        path = dialog.get_filename() if dialog.run() == Gtk.ResponseType.ACCEPT else None
        dialog.destroy()
        if not path or not os.path.isdir(path):
            return
        path = os.path.realpath(path)
        subprocess.run([WALLPAPER_SH, "add-dir", path])
        self.library = library()
        self.fill_places()
        self.navigate(path, Gtk.StackTransitionType.CROSSFADE)

    # ── Navigation ──────────────────────────────────────────────────
    def navigate(self, location, transition=Gtk.StackTransitionType.SLIDE_LEFT, remember=True):
        """Ort öffnen: LIBRARY oder ein Ordner. Leert das Suchfeld."""
        if location is not LIBRARY:
            location = os.path.realpath(location)
        if remember and location != self.location:
            self.history.append(self.location)
        same = location == self.location and not self.query_text()
        self.location = location
        self.entry.handler_block(self.changed_id)
        self.entry.set_text("")
        self.entry.handler_unblock(self.changed_id)
        self.completion_key = None
        self.store.clear()
        if self.refresh_id:
            GLib.source_remove(self.refresh_id)
            self.refresh_id = 0
        self.refresh(Gtk.StackTransitionType.NONE if same else transition)
        self.sync_places()

    def go_back(self):
        if self.history:
            self.navigate(self.history.pop(), Gtk.StackTransitionType.SLIDE_RIGHT, remember=False)

    def go_up(self):
        if self.location is LIBRARY:
            return
        parent = os.path.dirname(self.location.rstrip("/")) or "/"
        if parent != self.location:
            self.navigate(parent, Gtk.StackTransitionType.SLIDE_RIGHT)

    # ── Liste ───────────────────────────────────────────────────────
    def query_text(self):
        """Eingabe ohne den markierten Vorschlag der Autovervollständigung."""
        text = self.entry.get_text()
        bounds = self.entry.get_selection_bounds()
        if bounds and bounds[1] == len(text):
            text = text[: bounds[0]]
        return text

    def schedule_refresh(self):
        if self.refresh_id:
            GLib.source_remove(self.refresh_id)
        self.refresh_id = GLib.timeout_add(60, self.refresh)

    def refresh(self, transition=Gtk.StackTransitionType.NONE):
        if not isinstance(transition, Gtk.StackTransitionType):
            transition = Gtk.StackTransitionType.NONE   # Aufruf aus timeout_add
        self.refresh_id = 0
        text = self.query_text()
        if is_path_query(text):
            items, title, sub = self.path_items(text)
        elif self.location is LIBRARY:
            items, title, sub = self.library_items(text)
        else:
            items, title, sub = self.dir_items(self.location, text)
        if len(items) > MAX_ITEMS:
            sub += f"  ·  {len(items) - MAX_ITEMS} weitere – Suche verfeinern"
        page = self.page
        if transition != Gtk.StackTransitionType.NONE:
            page = self.pages[1] if self.page is self.pages[0] else self.pages[0]
        self.fill(page, items[:MAX_ITEMS])
        if page is not self.page:
            self.page = page
            self.stack.set_visible_child_full(page.page_id, transition)
        self.title.set_text(title)
        self.subtitle.set_text(sub)
        self.back.set_sensitive(bool(self.history))
        self.message.set_text(self.hint(text))
        return False

    def hint(self, text):
        if is_path_query(text):
            return "Tab vervollständigt  ·  Enter öffnet  ·  Esc leert die Eingabe"
        if self.location is LIBRARY:
            return "Klick übernimmt das Bild  ·  Ordner links öffnen  ·  Esc schließt"
        return "Klick auf einen Ordner öffnet ihn, auf ein Bild übernimmt es  ·  Alt+← zurück  ·  Esc schließt"

    def path_items(self, text):
        dir_disp, base = split_query(text)
        directory = expand(dir_disp)
        if not os.path.isdir(directory):
            return [], dir_disp, "Ordner nicht gefunden"
        dirs, imgs = listing(directory)
        d, i = visible(dirs, base), visible(imgs, base)
        if base and not d and not i:  # kein Anfang passt → enthaltener Text
            b = base.casefold()
            d = [n for n in dirs if b in n.casefold() and not n.startswith(".")]
            i = [n for n in imgs if b in n.casefold()]
        items = [("dir", os.path.join(directory, n), n) for n in d]
        items += [("img", os.path.join(directory, n), n) for n in i]
        return items, tilde(directory.rstrip("/") or "/"), f"Pfad  ·  {count_text(len(i), len(d))}"

    def dir_items(self, directory, text):
        dirs, imgs = listing(directory)
        dirs = ranked(text, [n for n in dirs if not n.startswith(".")], key=lambda n: n)
        imgs = ranked(text, [n for n in imgs if not n.startswith(".")], key=lambda n: n)
        items = [("dir", os.path.join(directory, n), n) for n in dirs]
        items += [("img", os.path.join(directory, n), n) for n in imgs]
        if not os.path.isdir(directory):
            sub = "Ordner nicht gefunden"
        elif text.strip():
            sub = f"Suche „{text.strip()}“  ·  {count_text(len(imgs), len(dirs))}"
        else:
            sub = f"{tilde(directory)}  ·  {count_text(len(imgs), len(dirs))}"
        return items, self.place_name(directory), sub

    def library_items(self, text):
        if not self.library:
            return [], "Alle Bilder", "Noch keine Hintergrund-Ordner – links einen Ort öffnen oder einen Ordner hinzufügen"
        paths = ranked(text, self.library,
                       key=lambda p: os.path.basename(os.path.dirname(p)) + "/" + os.path.basename(p))
        items = [("img", p, os.path.basename(p)) for p in paths]
        folders = len({os.path.dirname(p) for p in self.library})
        if text.strip():
            sub = f"Suche „{text.strip()}“  ·  {count_text(len(items), 0)}"
        else:
            sub = f"{count_text(len(items), 0)} aus {folders} {'Ordner' if folders == 1 else 'Ordnern'}"
        return items, "Alle Bilder", sub

    def fill(self, page, items):
        self.cancel_jobs()
        for child in page.flow.get_children():
            page.flow.remove(child)
        selected = None
        for kind, path, name in items:
            child = self.make_child(kind, path, name)
            page.flow.add(child)
            if selected is None and kind == "img" and path == self.current:
                selected = child
        page.flow.show_all()
        page.empty.set_visible(not items)
        child = selected or page.flow.get_child_at_index(0)
        if child is not None:
            page.flow.select_child(child)
        page.get_vadjustment().set_value(0)

    def make_child(self, kind, path, name):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        sf = max(1, self.get_scale_factor())
        label = Gtk.Label(label=name, ellipsize=Pango.EllipsizeMode.MIDDLE,
                          max_width_chars=22, width_chars=22)
        label.get_style_context().add_class("thumb-label")
        if kind == "img":
            thumb = Thumb(current=path == self.current)
            thumb.set_margin_bottom(6)
            box.pack_start(thumb, False, False, 0)
            box.pack_start(label, False, False, 0)
            self.want(("thumb", path), load_thumb, (path, THUMB_W * sf, THUMB_H * sf), thumb.set_pixbuf)
        else:
            # Ordner-Kachel: großes Ordnersymbol, bis die Vorschau da ist –
            # dann das erste Bild mit kleinem Ordner-Abzeichen
            overlay = Gtk.Overlay()
            overlay.set_margin_bottom(6)
            thumb = Thumb()
            overlay.add(thumb)
            # Symbol und Abzeichen schalten wir selbst um – no_show_all, damit
            # das show_all() nach dem Füllen sie nicht wieder einblendet
            big = Gtk.Image.new_from_icon_name("folder-symbolic", Gtk.IconSize.DIALOG)
            big.set_pixel_size(52)
            big.set_halign(Gtk.Align.CENTER)
            big.set_valign(Gtk.Align.CENTER)
            big.get_style_context().add_class("folder-icon")
            big.set_no_show_all(True)
            big.show()
            overlay.add_overlay(big)
            badge = Gtk.Box(halign=Gtk.Align.START, valign=Gtk.Align.END)
            badge.set_margin_start(8)
            badge.set_margin_bottom(8)
            badge.get_style_context().add_class("folder-badge")
            badge_icon = Gtk.Image.new_from_icon_name("folder-symbolic", Gtk.IconSize.MENU)
            badge_icon.show()
            badge.add(badge_icon)
            badge.set_no_show_all(True)
            overlay.add_overlay(badge)
            meta = Gtk.Label(label=" ")
            meta.get_style_context().add_class("thumb-meta")
            box.pack_start(overlay, False, False, 0)
            box.pack_start(label, False, False, 0)
            box.pack_start(meta, False, False, 0)

            def done(info, fresh):
                if info is None:
                    return
                n_imgs, n_dirs, preview = info
                meta.set_text(count_text(n_imgs, n_dirs))
                if preview is not None:
                    thumb.set_pixbuf(preview, fresh)
                    big.hide()
                    badge.show()

            self.want(("folder", path), folder_info, (path, THUMB_W * sf, THUMB_H * sf), done)
        child = Gtk.FlowBoxChild()
        child.add(box)
        child.item = (kind, path)
        child.set_tooltip_text(tilde(path))
        return child

    # ── Hintergrund-Aufträge (Vorschauen, Ordner-Infos) ─────────────
    def want(self, key, fn, args, callback):
        """callback(ergebnis, frisch) – sofort, wenn schon bekannt, sonst sobald
        der Auftrag im Hintergrund fertig ist (frisch=True → einblenden)."""
        if key in self.results:
            callback(self.results[key], False)
            return
        self.waiting.setdefault(key, []).append(callback)
        if key not in self.jobs:
            fut = self.pool.submit(fn, *args)
            self.jobs[key] = fut
            fut.add_done_callback(lambda f, k=key: GLib.idle_add(self.job_done, k, f))

    def job_done(self, key, fut):
        if self.jobs.get(key) is not fut:   # abgebrochen (und evtl. neu gestartet)
            return False
        del self.jobs[key]
        result = None if fut.cancelled() or fut.exception() else fut.result()
        if result is not None:
            self.results[key] = result
        for callback in self.waiting.pop(key, []):
            callback(result, True)
        return False

    def cancel_jobs(self):
        """Noch nicht begonnene Aufträge der bisherigen Ansicht verwerfen –
        sonst warten die Vorschauen des neuen Ordners hinter allen alten."""
        for key, fut in list(self.jobs.items()):
            if fut.cancel():
                del self.jobs[key]
                self.waiting.pop(key, None)

    # ── Autovervollständigung ───────────────────────────────────────
    def on_changed(self, _entry):
        text = self.entry.get_text()
        self.entry.set_icon_from_icon_name(Gtk.EntryIconPosition.SECONDARY,
                                           "edit-clear-symbolic" if text else None)
        key = None
        if is_path_query(text):
            dir_disp, base = split_query(text)
            key = (dir_disp, base.startswith("."))
        if key != self.completion_key:
            self.completion_key = key
            # erst nach dieser Eingabe neu füllen – die Vervollständigung
            # arbeitet gerade noch auf der bisherigen Liste
            GLib.idle_add(self.fill_completion, key)
        self.schedule_refresh()

    def fill_completion(self, key):
        if key != self.completion_key:
            return False
        self.store.clear()
        if key is not None:
            dir_disp, hidden = key
            dirs, imgs = listing(expand(dir_disp))
            for n in dirs[:500]:
                if hidden or not n.startswith("."):
                    self.store.append([dir_disp + n + "/"])
            for n in imgs[:500]:
                self.store.append([dir_disp + n])
        return False

    def on_match_selected(self, _completion, model, it):
        self.set_query(model[it][0])
        return True

    def complete(self):
        """Tab: Vorschlag annehmen bzw. bis zum gemeinsamen Anfang ergänzen."""
        text = self.entry.get_text()
        bounds = self.entry.get_selection_bounds()
        if bounds and bounds[1] == len(text) and bounds[0] < bounds[1]:
            self.set_query(text)
            return
        if not is_path_query(text):
            child = self.selected_child()
            if child is not None:
                child.grab_focus()
            return
        dir_disp, base = split_query(text)
        dirs, imgs = listing(expand(dir_disp))
        names = [n + "/" for n in visible(dirs, base)] + visible(imgs, base)
        if not names:
            self.entry.error_bell()
            return
        if len(names) == 1:
            self.set_query(dir_disp + names[0])
            return
        common = os.path.commonprefix([n.casefold() for n in names])
        prefix = names[0][: len(common)]
        if len(prefix) > len(base):
            self.set_query(dir_disp + prefix)
        else:
            self.entry.error_bell()

    def set_query(self, text):
        self.entry.set_text(text)
        self.entry.grab_focus_without_selecting()
        self.entry.set_position(-1)

    # ── Aktionen ────────────────────────────────────────────────────
    def selected_child(self):
        sel = self.flow.get_selected_children()
        return sel[0] if sel else self.flow.get_child_at_index(0)

    def activate_item(self, kind, path):
        if kind == "dir":
            self.navigate(path)
        else:
            self.apply(path)

    def apply(self, path):
        r = subprocess.run([WALLPAPER_SH, "set", path])
        if r.returncode == 0:
            self.destroy()
        else:
            self.message.set_text(f"Bild konnte nicht gesetzt werden: {tilde(path)}")

    def on_activate(self, _entry):
        text = self.entry.get_text()
        if is_path_query(text):
            path = expand(text)
            if os.path.isfile(path) and is_image(path):
                self.apply(path)
                return
            if os.path.isdir(path):
                self.navigate(path)
                return
        if self.refresh_id:  # Raster noch nicht aktuell
            GLib.source_remove(self.refresh_id)
            self.refresh()
        child = self.selected_child()
        if child is not None:
            self.activate_item(*child.item)

    def on_entry_icon(self, _entry, pos, _event):
        if pos == Gtk.EntryIconPosition.SECONDARY:
            self.entry.set_text("")
        self.entry.grab_focus_without_selecting()

    def on_entry_key(self, _entry, event):
        if event.keyval in (Gdk.KEY_Tab, Gdk.KEY_ISO_Left_Tab):
            self.complete()
            return True
        if event.keyval == Gdk.KEY_Down:
            child = self.selected_child()
            if child is not None:
                self.flow.select_child(child)
                child.grab_focus()
            return True
        return False

    def on_key(self, _win, event):
        alt = event.state & Gdk.ModifierType.MOD1_MASK
        if event.keyval == Gdk.KEY_Escape:
            if self.entry.get_text():
                self.entry.set_text("")
                self.entry.grab_focus_without_selecting()
            else:
                self.destroy()
            return True
        if alt and event.keyval == Gdk.KEY_Left:
            self.go_back()
            return True
        if alt and event.keyval == Gdk.KEY_Up:
            self.go_up()
            return True
        if event.keyval == Gdk.KEY_BackSpace and not self.entry.get_text():
            self.go_back()
            return True
        if not self.entry.has_focus():
            # Tippen im Raster landet im Suchfeld
            ctrl = event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK)
            uni = Gdk.keyval_to_unicode(event.keyval)
            if (32 <= uni != 127 and not ctrl) or event.keyval == Gdk.KEY_BackSpace:
                self.entry.grab_focus_without_selecting()
                self.entry.set_position(-1)
                return self.entry.event(event)
        return False

    def on_destroy(self, _win):
        self.pool.shutdown(wait=False, cancel_futures=True)
        Gtk.main_quit()


def acquire_lock():
    """Nur ein Fenster gleichzeitig. Läuft schon eins, wird es nach vorn geholt;
    ein hängender Prozess ohne Fenster wird beendet. Gibt die Sperre oder None zurück."""
    os.makedirs(RUNTIME, exist_ok=True)
    lock = open(os.path.join(RUNTIME, "wallpaper-picker.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock
    except OSError:
        pass
    focus = subprocess.run(["swaymsg", '[app_id="^i3apple-wallpaper$"] focus'],
                           capture_output=True, text=True)
    if focus.returncode == 0:
        return None
    pids = subprocess.run(["pgrep", "-f", r"wallpaper-picker\.py$"], capture_output=True, text=True).stdout
    for pid in pids.split():
        if pid.isdigit() and int(pid) != os.getpid():
            try:
                os.kill(int(pid), 15)
            except OSError:
                pass
    time.sleep(0.5)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return lock
    except OSError:
        raise RuntimeError("Eine ältere Hintergrund-Auswahl hängt und lässt sich nicht beenden.")


def main():
    lock = acquire_lock()
    if lock is None:
        return 0

    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = Picker()
    win.show_all()
    if win.library:
        win.refresh()
        win.sync_places()
    else:  # noch keine Bibliothek → direkt im Bilder-Ordner starten
        win.navigate(pictures_dir(), Gtk.StackTransitionType.NONE, remember=False)
    win.entry.grab_focus_without_selecting()
    threading.Thread(target=prune_thumbs, daemon=True).start()
    Gtk.main()
    return 0


if __name__ == "__main__":
    # Fehler mit vollständigem Ablauf auf stderr – wallpaper.sh schreibt das ins
    # Protokoll, meldet es und öffnet stattdessen das rofi-Raster
    sys.exit(main())
