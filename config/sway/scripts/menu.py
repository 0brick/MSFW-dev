#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════
#  i3-apple (Sway) · Menü- und Listenfenster (statt „rofi -dmenu“)
#
#  Liest Zeilen von stdin und zeigt sie als durchsuchbare Liste:
#    Spalte 1<TAB>Spalte 2<TAB>…[\0icon\x1fSymbolname]
#  Die Spalten stehen in allen Zeilen exakt untereinander (eine Breite je
#  Spalte über alle Zeilen). Das Fenster blendet beim Öffnen weich ein.
#
#  Aufruf:  menu.py [-p PLATZHALTER] [-m HINWEIS] [-w BREITE] [-l ZEILEN]
#                   [-a 1,4] [-f i|s]
#    -a  „aktive“ Zeilen (z. B. eingeschaltete Autostart-Apps), hervorgehoben
#    -f  Ausgabe: i = Nummer der Zeile (ab 0), s = Text (Spalten mit TAB)
#  Exit-Code 0 = Auswahl auf stdout, 1 = abgebrochen (Esc, Klick daneben).
#
#  Tastatur: tippen filtert, ↑/↓/Tab wählen, Bild↑/↓ blättern, Enter
#  übernimmt, Esc schließt. Ein Klick auf eine Zeile übernimmt sie sofort.
#  Fehlt GTK (python3-gi) oder scheitert der Aufbau, übernimmt rofi.
# ═══════════════════════════════════════════════════════════════════
import argparse
import os
import subprocess
import sys
import traceback

RUNTIME = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "sway-apple")
ROW_H = 42          # Zeilenhöhe in px: min-height 28 + padding 2×6 + margin 2×1 (CSS)
LIST_PAD = 12       # Innenabstand der Liste oben + unten (CSS .list)
ICON_PX = 28

CSS = b"""
window.menu { background-color: transparent; }
.panel {
  background-color: rgba(30, 30, 34, 0.88);
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 12px;
  color: #f5f5f7;
  font-family: "SF Pro Text", sans-serif;
  font-size: 13px;
  animation: menu-in 180ms cubic-bezier(0.22, 1, 0.36, 1);
}
@keyframes menu-in {
  from { opacity: 0; }
  to   { opacity: 1; }
}
/* Die Liste gleitet zusätzlich ein Stück nach oben. Die Höhe des
   Scrollbereichs ist fest, das Fenster ändert dabei seine Größe nicht. */
@keyframes list-in {
  from { opacity: 0; margin-top: 10px; }
  to   { opacity: 1; margin-top: 0; }
}
.panel scrolledwindow, .panel viewport { background-color: transparent; border: none; }

.search { padding: 14px 16px 10px 16px; }
.search image.lens { color: rgba(245, 245, 247, 0.55); }
entry.query {
  all: unset;
  min-height: 30px;
  color: #f5f5f7;
  caret-color: #0a84ff;
  font-family: "SF Pro Display", "SF Pro Text", sans-serif;
  font-size: 18px;
}
entry.query selection { background-color: rgba(10, 132, 255, 0.45); color: #ffffff; }
.mesg {
  color: rgba(245, 245, 247, 0.55);
  font-size: 11px;
  padding: 0 18px 10px 18px;
}

.list {
  background-color: transparent;
  padding: 6px 8px;
  animation: list-in 260ms cubic-bezier(0.22, 1, 0.36, 1);
}
.divider { min-height: 1px; background-color: rgba(255, 255, 255, 0.10); }
.list row {
  min-height: 28px;
  padding: 6px 10px;
  margin: 1px 0;
  border: none;
  border-radius: 8px;
  box-shadow: none;
  background-color: transparent;
  color: #f5f5f7;
  transition: background-color 120ms ease;
}
.list row:hover { background-color: rgba(255, 255, 255, 0.07); }
.list row:selected, .list row:selected:hover { background-color: rgba(10, 132, 255, 0.85); }
.list row label { color: #f5f5f7; }
.list row.active label { color: #64d2ff; }
.list row:selected label, .list row:selected.active label { color: #ffffff; }
.list row .col-first { font-weight: 600; }
.list row .col-dim { color: rgba(245, 245, 247, 0.55); }
.list row:selected .col-dim { color: rgba(255, 255, 255, 0.80); }
.empty { color: rgba(245, 245, 247, 0.55); padding: 18px; }
"""


def parse_rows(data):
    """rofi-Format: Text[\\0schlüssel\\x1fwert…] je Zeile → [(spalten, icon)]."""
    rows = []
    lines = data.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for line in lines:
        text, _, meta = line.partition("\0")
        icon = ""
        if meta:
            parts = meta.split("\x1f")
            for key, value in zip(parts[0::2], parts[1::2]):
                if key == "icon":
                    icon = value
        rows.append((text.split("\t"), icon))
    return rows


def run_rofi(args, rows):
    """Ersatz ohne GTK: dasselbe Menü mit rofi (Spalten mit „·“ verbunden)."""
    theme = 'window { width: %dpx; } listview { lines: %d; } entry { placeholder: "%s"; }' % (
        args.width, args.lines, args.prompt.replace('"', "'"))
    cmd = ["rofi", "-dmenu", "-i", "-p", "", "-no-custom", "-format", args.format,
           "-theme-str", theme]
    if args.message:
        cmd += ["-mesg", args.message]
    if args.active:
        cmd += ["-a", args.active]
    data = "".join("%s%s\n" % ("   ·   ".join(cols), "\0icon\x1f" + icon if icon else "")
                   for cols, icon in rows)
    try:
        res = subprocess.run(cmd, input=data.encode(), stdout=subprocess.PIPE)
    except OSError:
        return 1
    sys.stdout.buffer.write(res.stdout)
    return res.returncode


def log_error():
    try:
        os.makedirs(RUNTIME, exist_ok=True)
        with open(os.path.join(RUNTIME, "menu.log"), "a") as f:
            traceback.print_exc(file=f)
    except OSError:
        pass
    traceback.print_exc()


def build(args, rows):
    """Stylesheet laden und das Fenster aufbauen (noch nicht anzeigen)."""
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GLib
    GLib.set_prgname("i3apple-menu")   # Wayland-app_id für die Fensterregel in Sway
    from gi.repository import Gdk, GdkPixbuf, Gtk, Pango

    active = set()
    for part in (args.active or "").split(","):
        if part.strip().isdigit():
            active.add(int(part))

    class Menu(Gtk.Window):
        def __init__(self):
            super().__init__(title=args.prompt or "Menü")
            self.result = None
            self.had_focus = False
            self.set_decorated(False)
            self.set_default_size(args.width, -1)
            screen = self.get_screen()
            visual = screen.get_rgba_visual()
            if visual is not None and screen.is_composited():
                self.set_visual(visual)
                self.set_app_paintable(True)
            self.get_style_context().add_class("menu")

            panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            panel.get_style_context().add_class("panel")
            self.add(panel)

            # ── Suchfeld ──
            search = Gtk.Box(spacing=12)
            search.get_style_context().add_class("search")
            lens = Gtk.Image.new_from_icon_name("system-search-symbolic", Gtk.IconSize.LARGE_TOOLBAR)
            lens.get_style_context().add_class("lens")
            search.pack_start(lens, False, False, 0)
            self.entry = Gtk.Entry(hexpand=True)
            self.entry.get_style_context().add_class("query")
            self.entry.set_placeholder_text(args.prompt or "Suchen")
            self.entry.connect("changed", self.on_changed)
            self.entry.connect("activate", lambda _e: self.choose_selected())
            search.pack_start(self.entry, True, True, 0)
            panel.pack_start(search, False, False, 0)
            if args.message:
                mesg = Gtk.Label(label=args.message, xalign=0, wrap=True)
                mesg.get_style_context().add_class("mesg")
                panel.pack_start(mesg, False, False, 0)
            divider = Gtk.Box()
            divider.get_style_context().add_class("divider")
            panel.pack_start(divider, False, False, 0)

            # ── Liste: feste Höhe, damit das Fenster beim Filtern nicht springt ──
            self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE)
            self.listbox.set_activate_on_single_click(True)
            self.listbox.get_style_context().add_class("list")
            # vor dem Einfügen setzen: GTK ruft den Filter schon beim add() auf
            self.shown = set(range(len(rows)))
            self.listbox.set_filter_func(lambda row: row.index in self.shown)
            self.listbox.connect("row-activated", lambda _l, row: self.choose(row.index))
            self.empty = Gtk.Label(label="Keine Treffer")
            self.empty.get_style_context().add_class("empty")
            self.empty.set_no_show_all(True)
            self.content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.content.pack_start(self.listbox, False, False, 0)
            self.content.pack_start(self.empty, False, False, 0)
            self.scroll = Gtk.ScrolledWindow()
            self.scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            height = max(1, min(len(rows), args.lines)) * ROW_H + LIST_PAD
            self.scroll.set_min_content_height(height)
            self.scroll.set_max_content_height(height)
            self.scroll.add(self.content)
            panel.pack_start(self.scroll, True, True, 0)

            # Eine Breite je Spalte über alle Zeilen: SizeGroups. Die erste und
            # (ab drei Spalten) die letzte Spalte richten sich nach dem längsten
            # Eintrag, die Spalten dazwischen füllen den Rest und kürzen mit „…“.
            self.groups = {}
            self.rows = []
            for index, (cols, icon) in enumerate(rows):
                row = self.make_row(index, cols, icon)
                self.rows.append(row)
                self.listbox.add(row)
            self.visible = list(self.rows)

            self.connect("key-press-event", self.on_key)
            self.connect("focus-in-event", self.on_focus_in)
            self.connect("focus-out-event", self.on_focus_out)
            self.connect("destroy", lambda _w: Gtk.main_quit())

        def group(self, key):
            if key not in self.groups:
                self.groups[key] = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
            return self.groups[key]

        def make_icon(self, name):
            if name.startswith("/"):
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_size(name, ICON_PX, ICON_PX)
                    return Gtk.Image.new_from_pixbuf(pb)
                except GLib.Error:
                    name = "application-x-executable"
            img = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.DND)
            img.set_pixel_size(ICON_PX)
            return img

        def make_row(self, index, cols, icon):
            row = Gtk.ListBoxRow()
            row.index = index
            row.search = " ".join(cols).casefold()
            if index in active:
                row.get_style_context().add_class("active")
            box = Gtk.Box(spacing=16)
            if icon:
                img = self.make_icon(icon)
                img.set_valign(Gtk.Align.CENTER)
                box.pack_start(img, False, False, 0)
                box.set_spacing(12)
                inner = Gtk.Box(spacing=16)
                box.pack_start(inner, True, True, 0)
            else:
                inner = box
            n = len(cols)
            for i, text in enumerate(cols):
                label = Gtk.Label(label=text, xalign=0, valign=Gtk.Align.CENTER)
                label.set_ellipsize(Pango.EllipsizeMode.END)
                ctx = label.get_style_context()
                expand = False
                if n == 1:
                    expand = True
                elif i == 0:
                    ctx.add_class("col-first")
                    label.set_max_width_chars(34)
                    self.group(("first", n)).add_widget(label)
                elif i == n - 1 and n >= 3:
                    ctx.add_class("col-dim")
                    label.set_xalign(1)
                    label.set_max_width_chars(20)
                    self.group(("last", n)).add_widget(label)
                else:
                    expand = True
                inner.pack_start(label, expand, expand, 0)
            row.add(box)
            return row

        # ── Filtern & Auswahl ──
        def on_changed(self, _entry):
            words = self.entry.get_text().casefold().split()
            self.visible = [r for r in self.rows if all(w in r.search for w in words)]
            self.shown = {r.index for r in self.visible}
            self.listbox.invalidate_filter()
            self.empty.set_visible(not self.visible)
            self.scroll.get_vadjustment().set_value(0)
            self.select(0)

        def select(self, pos):
            if not self.visible:
                self.listbox.unselect_all()
                return
            pos = max(0, min(pos, len(self.visible) - 1))
            row = self.visible[pos]
            self.listbox.select_row(row)
            GLib.idle_add(self.scroll_to, row)

        def scroll_to(self, row):
            # PyGObject liefert (x, y) bzw. None, ohne Override (ok, x, y)
            coords = row.translate_coordinates(self.content, 0, 0)
            if not coords or coords[0] is False:
                return False
            y, h = coords[-1], row.get_allocated_height()
            adj = self.scroll.get_vadjustment()
            if y < adj.get_value():
                adj.set_value(y)
            elif y + h > adj.get_value() + adj.get_page_size():
                adj.set_value(y + h - adj.get_page_size())
            return False

        def current(self):
            row = self.listbox.get_selected_row()
            return self.visible.index(row) if row in self.visible else -1

        def choose_selected(self):
            row = self.listbox.get_selected_row()
            if row is not None and row in self.visible:
                self.choose(row.index)

        def choose(self, index):
            cols = rows[index][0]
            self.result = str(index) if args.format == "i" else "\t".join(cols)
            self.close_menu()

        def close_menu(self):
            self.had_focus = False   # kein zweites Schließen über focus-out
            self.destroy()

        def on_key(self, _win, event):
            key = event.keyval
            step = max(1, args.lines - 1)
            if key == Gdk.KEY_Escape:
                self.close_menu()
            elif key in (Gdk.KEY_Down, Gdk.KEY_Tab, Gdk.KEY_KP_Down):
                self.select(self.current() + 1)
            elif key in (Gdk.KEY_Up, Gdk.KEY_ISO_Left_Tab, Gdk.KEY_KP_Up):
                self.select(self.current() - 1)
            elif key in (Gdk.KEY_Page_Down, Gdk.KEY_KP_Page_Down):
                self.select(self.current() + step)
            elif key in (Gdk.KEY_Page_Up, Gdk.KEY_KP_Page_Up):
                self.select(self.current() - step)
            elif key in (Gdk.KEY_KP_Enter, Gdk.KEY_ISO_Enter):
                self.choose_selected()
            else:
                return False
            return True

        # Wie rofi: Klick daneben (Fokus geht an ein anderes Fenster) schließt
        def on_focus_in(self, *_a):
            self.had_focus = True
            return False

        def on_focus_out(self, *_a):
            if self.had_focus:
                GLib.idle_add(self.close_menu)
            return False

    css = Gtk.CssProvider()
    css.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), css,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    return Menu()


def run_gtk(args, rows):
    win = build(args, rows)
    win.show_all()
    win.select(0)
    win.entry.grab_focus()
    return win


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="i3-apple Menü (Ersatz für rofi -dmenu)")
    ap.add_argument("-p", "--prompt", default="")
    ap.add_argument("-m", "--message", default="")
    ap.add_argument("-w", "--width", type=int, default=560)
    ap.add_argument("-l", "--lines", type=int, default=10)
    ap.add_argument("-a", "--active", default="")
    ap.add_argument("-f", "--format", choices=("i", "s"), default="i")
    return ap.parse_args(argv)


def main():
    args = parse_args()
    rows = parse_rows(sys.stdin.buffer.read().decode("utf-8", "replace"))
    if not rows:
        return 1

    try:
        win = run_gtk(args, rows)
    except Exception:   # kein GTK, kein Bildschirm … → rofi
        log_error()
        return run_rofi(args, rows)

    from gi.repository import Gtk
    Gtk.main()
    if win.result is None:
        return 1
    sys.stdout.write(win.result + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
