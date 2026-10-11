#!/usr/bin/env python3
# Gibt die Bildschirme so aus, wie GTK (und damit eww) sie nummeriert:
#   <nummer>\t<x>\t<y>
# launch-bars.sh ordnet sie über die Position den Sway-Ausgängen zu –
# unter Wayland ist das zuverlässiger als Namen oder Reihenfolge.
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk  # noqa: E402,F401  (Gtk initialisiert die Anzeige)

display = Gdk.Display.get_default()
if display is not None:
    for i in range(display.get_n_monitors()):
        g = display.get_monitor(i).get_geometry()
        print(f"{i}\t{g.x}\t{g.y}")
