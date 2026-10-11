#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  i3-apple · Sway-Variante · Selbsttest
#
#  sway/test.sh          alles prüfen (ändert nichts, öffnet keine Fenster)
#  sway/test.sh --gui    zusätzlich Hintergrund-Auswahl und Bildschirm-Fenster
#                        kurz öffnen (je ~4 Sekunden) und eine Testmitteilung senden
#
#  Am aussagekräftigsten in der laufenden Sitzung „Sway (i3-apple)“ (z. B. im
#  kitty-Terminal). Außerhalb davon werden Laufzeit-Prüfungen übersprungen.
#  Ergebnis: ✓ in Ordnung · ! Hinweis/optional · ✗ Fehler (Exit-Code = Anzahl Fehler)
# ═══════════════════════════════════════════════════════════════════
GUI=0
case ${1:-} in
  --gui) GUI=1 ;;
  -h|--help) sed -n '3,/^# ═/{/^# ═/!p}' "$0"; exit 0 ;;
  "") ;;
  # 64 (EX_USAGE) statt 2 – der Exit-Code zählt sonst die Fehler
  *) echo "Unbekannte Option: $1 (erlaubt: --gui, --help)" >&2; exit 64 ;;
esac

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
SW="$CFG/sway"
S="$SW/scripts"
E="$SW/eww"
SETTINGS="$CFG/i3-apple"
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/sway-apple-test.XXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0 WARN=0 FAIL=0
ok()      { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
hint()    { printf '  \033[33m!\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
bad()     { printf '  \033[31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
info()    { printf '    \033[2m%s\033[0m\n' "$*"; }
section() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
have()    { command -v "$1" >/dev/null 2>&1; }

# need <befehl> <wofür>   – Pflicht
need() { if have "$1"; then ok "$1 – $2"; else bad "$1 fehlt – $2"; fi; }
# want <befehl> <wofür>   – optional
want() { if have "$1"; then ok "$1 – $2"; else hint "$1 fehlt (optional) – $2"; fi; }

proc() { pgrep -u "$USER" -f "$1" >/dev/null 2>&1; }

IN_SWAY=0
[[ -n ${SWAYSOCK:-} ]] && swaymsg -t get_version >/dev/null 2>&1 && IN_SWAY=1

printf '\033[1mi3-apple · Sway-Selbsttest\033[0m  (%s)\n' "$(date '+%d.%m.%Y %H:%M')"

# ── Sitzung ─────────────────────────────────────────────────────────
section "Sitzung"
if (( IN_SWAY )); then
  v=$(swaymsg -t get_version -r | jq -r '.human_readable // .version' 2>/dev/null)
  ok "Läuft in Sway ($v)"
else
  hint "Nicht in einer laufenden Sway-Sitzung – Laufzeit-Prüfungen werden übersprungen"
fi
[[ ${XDG_SESSION_TYPE:-} == wayland ]] && ok "Wayland-Sitzung" || hint "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-leer} (erwartet: wayland)"
if [[ ${DCONF_PROFILE:-} == *i3-apple* ]]; then
  ok "Sitzung „Sway (i3-apple)“ (env-sway.sh geladen, eigene dconf-Datenbank)"
elif (( IN_SWAY )); then
  bad "env-sway.sh nicht geladen – am Anmeldebildschirm „Sway (i3-apple)“ statt „Sway“ wählen"
fi
[[ :$PATH: == *":$SW/bin:"* ]] && ok "PATH enthält ~/.config/sway/bin (rofi im Sway-Design)" \
  || { (( IN_SWAY )) && bad "~/.config/sway/bin fehlt im PATH" || info "PATH ohne ~/.config/sway/bin (nur in der Sitzung nötig)"; }
[[ ${KITTY_CONFIG_DIRECTORY:-} == "$SW/kitty" ]] && ok "kitty nutzt ~/.config/sway/kitty" \
  || { (( IN_SWAY )) && hint "KITTY_CONFIG_DIRECTORY nicht gesetzt"; }
for f in /usr/share/wayland-sessions/sway-apple.desktop /usr/local/bin/sway-apple-session; do
  [[ -f $f ]] && ok "Anmeldesitzung: $f" || bad "Anmeldesitzung fehlt: $f (sway/install.sh ausführen)"
done

# ── Programme ───────────────────────────────────────────────────────
section "Programme"
need sway       "Compositor"
need swaymsg    "Steuerung (alle Skripte)"
# wie env-sway.sh: zuerst das selbst gebaute SwayFX (install.sh → build_swayfx), sonst
# das System-Sway an der Versionszeile oder am Programm (nur SwayFX kennt corner_radius)
FX_BIN="$HOME/.local/share/i3-apple/swayfx/bin/sway"   # fester Pfad wie in install.sh/env-sway.sh
fx_built_ok() { [[ -x $FX_BIN ]] && "$FX_BIN" --version >/dev/null 2>&1; }
is_swayfx() {
  fx_built_ok || { have sway && { sway --version 2>/dev/null | grep -qi swayfx || grep -qa corner_radius "$(command -v sway)"; }; }
}
if [[ -e $FX_BIN ]]; then
  if fx_built_ok; then
    ok "Selbst gebautes SwayFX: $("$FX_BIN" --version 2>/dev/null | head -n1)"
    if (( IN_SWAY )) && [[ $(command -v sway) != "$FX_BIN" && $(readlink -f "$(command -v sway)") != "$(readlink -f "$FX_BIN")" ]]; then
      hint "Die Sitzung nutzt noch das System-Sway – ab- und wieder anmelden"
    fi
  else
    bad "Selbst gebautes SwayFX startet nicht mehr (System-Update?) – sway/install.sh baut es neu"
  fi
fi
if is_swayfx; then
  ok "SwayFX erkannt – Unschärfe, Schatten, runde Ecken"
  [[ -f $RUNTIME/no-effects ]] && hint "Effekte sind ausgeschaltet (Super+Shift+A schaltet sie wieder ein)"
  [[ -f $RUNTIME/gamemode ]] && hint "Spielmodus aktiv – Effekte bleiben bis zu seinem Ende aus"
  fxb=$FX_BIN; fx_built_ok || fxb=$(command -v sway)
  if grep -qa animation_duration_ms "$fxb" 2>/dev/null; then
    ok "SwayFX kann Animationen (Fenster, Arbeitsflächen)"
  else
    hint "SwayFX ohne Animationen (erst ab 0.6) – sway/install.sh versucht, es nachzurüsten"
  fi
else
  bad "SwayFX fehlt (Pflicht) – sway/install.sh baut es, Protokoll ~/.cache/i3-apple/swayfx-build.log"
fi
need Xwayland   "X11-Programme"
need swaybg     "Hintergrundbild"
need swayidle   "Bildschirmsperre nach Inaktivität"
need swaylock   "Sperrbildschirm"
if have fprintd-verify; then
  if timeout 5 bash "$S/fingerprint.sh" available 2>/dev/null; then
    ok "Fingerabdruck entsperrt den Sperrbildschirm (fprintd, eingerichtete Finger)"
  else
    hint "Fingerabdruck nicht nutzbar: kein Leser, kein eingerichteter Finger oder swaylock älter als 1.6"
  fi
else
  info "Kein fprintd – Sperrbildschirm nur mit Passwort"
fi
need kanshi     "Bildschirmprofile beim Anstecken"
need jq         "JSON (Menüleiste, Skripte)"
need python3    "Fenster für Hintergrund und Bildschirme"
need dunst      "Mitteilungen"
need dunstctl   "„Nicht stören“"
need notify-send "Mitteilungen senden"
need kitty      "Terminal"
need dex        "Apps & Autostart starten"
need wl-copy    "Zwischenablage"
need wl-paste   "Zwischenablage"
need grim       "Bildschirmfotos"
need slurp      "Bereich auswählen"
need nmcli      "WLAN-Popup"
need bluetoothctl "Bluetooth-Popup"
need pactl      "Ton-Popup"
need playerctl  "Medientasten"
if have magick || have convert; then ok "ImageMagick – Sperrbildschirm-Unschärfe"; else bad "ImageMagick fehlt – Sperrbildschirm-Unschärfe"; fi
if have cliphist || have clipman; then ok "Zwischenablage-Verlauf ($(have cliphist && echo cliphist || echo clipman))"; else bad "cliphist/clipman fehlt – Zwischenablage-Verlauf (Super+V)"; fi
want xsettingsd  "GTK-Einstellungen für X-Programme"
want brightnessctl "Helligkeit"
want powerprofilesctl "Energiemodus"
want rofimoji    "Emoji-Auswahl"
want wtype       "Emoji direkt eintippen"
want swappy      "Bildschirmfoto bearbeiten"
want wf-recorder "Bildschirmaufnahme (Video)"
want wl-mirror   "Bildschirme spiegeln"
want gammastep   "Blaulichtfilter"
want tesseract   "Texterkennung (OCR)"
if have tesseract; then
  langs=$(tesseract --list-langs 2>/dev/null)
  for l in deu eng; do grep -qx "$l" <<<"$langs" && ok "OCR-Sprache $l" || hint "OCR-Sprache $l fehlt (tesseract-ocr-$l)"; done
fi

# eww mit Wayland
eww_bin=$(command -v eww 2>/dev/null || echo "$HOME/.local/bin/eww")
if [[ -x $eww_bin ]]; then
  if ldd "$eww_bin" 2>/dev/null | grep -q gtk-layer-shell; then
    ok "eww mit Wayland/Layer-Shell ($eww_bin)"
  else
    bad "eww ohne Wayland-Unterstützung ($eww_bin) – sway/install.sh baut es neu"
  fi
else
  bad "eww fehlt – Menüleiste"
fi

# rofi: welches wird in der Sitzung benutzt?
real_rofi=""
IFS=: read -ra path_dirs <<<"$PATH"   # PATH-Einträge dürfen Leerzeichen enthalten
for d in "$DATA/i3-apple/rofi-wayland/bin" "${path_dirs[@]}"; do
  [[ -x $d/rofi && $(readlink -f "$d/rofi") != "$(readlink -f "$SW/bin/rofi" 2>/dev/null)" ]] && { real_rofi=$d/rofi; break; }
done
if [[ -n $real_rofi ]]; then
  rv=$("$real_rofi" -v 2>/dev/null | head -n1)
  if ldd "$real_rofi" 2>/dev/null | grep -q libwayland-client; then
    ok "rofi mit Wayland ($rv, $real_rofi)"
  else
    hint "rofi ohne Wayland ($rv) – läuft über XWayland"
  fi
else
  bad "rofi fehlt – Launcher und alle Menüs"
fi

# ── Konfiguration ───────────────────────────────────────────────────
section "Konfiguration"
[[ -f $SW/config ]] && ok "~/.config/sway/config" || bad "~/.config/sway/config fehlt (sway/install.sh)"
[[ -e $SW/.i3-apple ]] && ok "Konfiguration stammt von i3-apple" || hint "~/.config/sway ohne i3-apple-Markierung"
[[ -f $SW/fx.conf ]] && ok "fx.conf vorhanden ($( [[ -s $SW/fx.conf ]] && echo 'SwayFX-Effekte' || echo 'leer – normales Sway'))" \
  || bad "~/.config/sway/fx.conf fehlt – Sway meldet sonst einen Fehler"
if [[ -s $SW/fx.conf ]] && ! is_swayfx; then
  bad "fx.conf enthält SwayFX-Befehle, aber SwayFX läuft nicht"
elif [[ ! -s $SW/fx.conf ]] && is_swayfx; then
  bad "SwayFX läuft, aber fx.conf ist leer – keine runden Ecken (neu anmelden oder sway/install.sh --config-only)"
fi
if have sway && [[ -f $SW/config ]]; then
  if out=$(sway -C -c "$SW/config" 2>&1); then
    ok "Sway-Konfiguration ist gültig (sway -C)"
  else
    bad "Sway-Konfiguration hat Fehler:"; grep -iE 'error|fehler' <<<"$out" | head -n 8 | while read -r l; do info "$l"; done
  fi
fi
for f in "$E/eww.yuck" "$E/eww.scss" "$SW/rofi/config.rasi" "$SW/rofi/spotlight.rasi" \
         "$SW/dunst/dunstrc" "$SW/kitty/kitty.conf" "$SETTINGS/env-sway.sh" "$SETTINGS/dconf-profile" \
         "$SETTINGS/xsettingsd.conf" "$SETTINGS/input" "$SETTINGS/favorites"; do
  [[ -f $f ]] && ok "${f/#$HOME/\~}" || bad "fehlt: ${f/#$HOME/\~}"
done
grep -q '@EWW@' "$E/eww.yuck" 2>/dev/null && bad "eww.yuck enthält noch @EWW@ (Pfad nicht ersetzt)"
grep -q "$SW/rofi/spotlight.rasi" "$SW/rofi/config.rasi" 2>/dev/null \
  && ok "rofi nutzt das eigene Spotlight-Theme" || bad "rofi-Konfiguration verweist nicht auf ~/.config/sway/rofi/spotlight.rasi"

# Skripte: ausführbar und syntaktisch korrekt
nx=0 syn=0
for f in "$S"/*.sh "$E"/scripts/*.sh "$SW"/bin/*; do
  [[ -f $f ]] || continue
  [[ -x $f ]] || { bad "nicht ausführbar: ${f/#$HOME/\~}"; nx=$((nx + 1)); }
  head -n1 "$f" | grep -q bash && { bash -n "$f" 2>"$TMP/syn" || { bad "Syntaxfehler: ${f/#$HOME/\~}"; info "$(head -n1 "$TMP/syn")"; syn=$((syn + 1)); }; }
  head -n1 "$f" | grep -q '/bin/sh' && { sh -n "$f" 2>/dev/null || { bad "Syntaxfehler: ${f/#$HOME/\~}"; syn=$((syn + 1)); }; }
done
for f in "$S"/*.py "$E"/scripts/*.py; do
  [[ -f $f ]] || continue
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$f" 2>"$TMP/syn" \
    || { bad "Python-Syntaxfehler: ${f/#$HOME/\~}"; info "$(tail -n1 "$TMP/syn")"; syn=$((syn + 1)); }
done
(( nx == 0 && syn == 0 )) && ok "Alle Skripte ausführbar und ohne Syntaxfehler"

# rofi-Theme lässt sich laden
if [[ -n $real_rofi && -f $SW/rofi/config.rasi ]]; then
  if "$real_rofi" -config "$SW/rofi/config.rasi" -dump-theme >/dev/null 2>"$TMP/rofi"; then
    ok "rofi-Theme lädt ohne Fehler"
  else
    bad "rofi-Theme fehlerhaft"; info "$(head -n2 "$TMP/rofi")"
  fi
fi

# ── Design: Schriften, Themes, Symbole ──────────────────────────────
section "Design"
fonts=$(fc-list : family 2>/dev/null)
for f in "SF Pro Text" "SF Pro Display"; do
  grep -qiF "$f" <<<"$fonts" && ok "Schrift $f" || hint "Schrift $f fehlt – Ersatzschrift wird genutzt"
done
if grep -qiF "SF Mono" <<<"$fonts"; then ok "Schrift SF Mono (Terminal)"
elif grep -qiF "JetBrains Mono" <<<"$fonts"; then ok "Schrift JetBrains Mono (Ersatz für SF Mono)"
else hint "Weder SF Mono noch JetBrains Mono – kitty nutzt die Monospace-Schrift des Systems"; fi
theme_dir() { local d; for d in "$HOME/.themes" "$DATA/themes" /usr/share/themes; do [[ -d $d/$1 ]] && return 0; done; return 1; }
icon_dir()  { local d; for d in "$HOME/.icons" "$DATA/icons" /usr/share/icons; do [[ -d $d/$1 ]] && return 0; done; return 1; }
for t in WhiteSur-Dark WhiteSur-Light; do theme_dir "$t" && ok "GTK-Theme $t" || hint "GTK-Theme $t fehlt"; done
for t in WhiteSur WhiteSur-dark; do icon_dir "$t" && ok "Symbole $t" || hint "Symbol-Theme $t fehlt"; done
icon_dir macOS && ok "Mauszeiger macOS" || hint "Mauszeiger-Theme macOS fehlt"
# Menüleiste: eigenes Symbol-Theme (eww.scss → -gtk-icon-theme), unabhängig von dconf
grep -q 'i3apple-sway-bar' "$E/eww.scss" 2>/dev/null && ok "Menüleiste nutzt ihr eigenes Symbol-Theme" \
  || bad "eww.scss ohne Symbol-Theme der Menüleiste – Symbole hängen von gsettings ab (sway/install.sh --config-only)"
if [[ -f $E/scripts/bar-icons.py ]]; then
  out=$(python3 "$E/scripts/bar-icons.py" check 2>&1); rc=$?
  case $rc in
    0) ok "$out" ;;
    1) bad "$out"; info "Neu abgleichen: python3 ~/.config/sway/eww/scripts/bar-icons.py" ;;
    *) hint "$out" ;;
  esac
fi

# ── Python & GTK (Hintergrund-Auswahl, Bildschirme, Menüleiste) ─────
section "Python & GTK"
if [[ -z ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
  hint "Keine Anzeige – GTK-Prüfungen übersprungen (in der Sway-Sitzung ausführen)"
else
  cat > "$TMP/gtk_check.py" <<'PY'
import importlib.util, os, sys
S = sys.argv[1]
def out(kind, msg): print(f"{kind}\t{msg}", flush=True)

try:
    import gi
    for ns, v in (("Gtk", "3.0"), ("Gdk", "3.0"), ("GdkPixbuf", "2.0"), ("PangoCairo", "1.0")):
        gi.require_version(ns, v)
    from gi.repository import Gdk, GdkPixbuf, Gtk, PangoCairo  # noqa: F401
    out("OK", f"GTK {Gtk.get_major_version()}.{Gtk.get_minor_version()}.{Gtk.get_micro_version()} "
              f"mit PyGObject {gi.__version__}")
except Exception as e:
    out("FAIL", f"GTK 3 für Python (python3-gi, gir1.2-gtk-3.0): {e}")
    sys.exit(0)

try:
    import cairo
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8)
    cr = cairo.Context(surf)
    pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 8, 8)
    Gdk.cairo_set_source_pixbuf(cr, pb, 0, 0)
    cr.paint()
    out("OK", "Cairo-Anbindung (python3-gi-cairo) – Vorschaubilder")
except Exception as e:
    out("FAIL", f"Cairo-Anbindung (python3-gi-cairo): {e}")

fmts = {f.get_name() for f in GdkPixbuf.Pixbuf.get_formats()}
for f, need in (("png", True), ("jpeg", True), ("svg", True), ("webp", False)):
    note = " – alle Symbole, Paket librsvg2-common" if f == "svg" else ""
    out("OK" if f in fmts else ("FAIL" if need else "WARN"), f"Bildformat {f.upper()} (gdk-pixbuf){note}")

display = Gdk.Display.get_default()
out("OK", f"GTK sieht {display.get_n_monitors()} Bildschirm(e)")

theme = Gtk.IconTheme.new()
theme.set_custom_theme("WhiteSur-dark")
icons = ["view-app-grid-symbolic", "bluetooth-active-symbolic", "network-wireless-signal-good-symbolic",
         "audio-volume-high-symbolic", "battery-level-50-symbolic", "notifications-disabled-symbolic",
         "display-brightness-symbolic", "system-search-symbolic", "folder-symbolic",
         # Hintergrund-Auswahl: Seitenleiste, Zurück, Suchfeld
         "folder-pictures-symbolic", "user-home-symbolic", "image-x-generic-symbolic",
         "go-previous-symbolic", "list-add-symbolic", "edit-clear-symbolic",
         "preferences-desktop-display", "preferences-desktop-wallpaper", "system-lock-screen"]
missing = [i for i in icons if not theme.has_icon(i)]
if missing:
    out("WARN", "Symbole fehlen (WhiteSur-dark + Ersatz): " + ", ".join(missing))
else:
    out("OK", f"Alle {len(icons)} geprüften Menüleisten-/Menü-Symbole vorhanden")

# So sehen es GTK-Fenster der Sitzung (Hintergrund-Auswahl, Bildschirme); die
# Menüleiste hat ihr eigenes Theme (Abschnitt „Design“)
active = Gtk.Settings.get_default().get_property("gtk-icon-theme-name")
missing = [i for i in icons if not Gtk.IconTheme.get_default().has_icon(i)]
if missing:
    out("FAIL", f"Mit dem aktiven Symbol-Theme „{active}“ fehlen: " + ", ".join(missing))
else:
    out("OK", f"Aktives Symbol-Theme „{active}“ liefert alle Symbole")

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

# Hintergrund-Auswahl: CSS laden und Fenster aufbauen (ohne es anzuzeigen)
try:
    picker = load("picker", os.path.join(S, "wallpaper-picker.py"))
    css = Gtk.CssProvider()
    css.load_from_data(picker.CSS)
    out("OK", "Hintergrund-Auswahl: Stylesheet gültig")
    win = picker.Picker()
    win.refresh()
    n = len(win.flow.get_children())
    out("OK", f"Hintergrund-Auswahl: Fenster lässt sich aufbauen ({len(win.library)} Bilder in der Bibliothek, {n} angezeigt)")
    item = picker.load_thumb(win.library[0], 64, 40) if win.library else None
    if win.library:
        out("OK" if item is not None else "FAIL", "Hintergrund-Auswahl: Vorschaubild erzeugen")
        # Ordner öffnen wie per Klick (ohne Übergang) und Ordner-Kachel vorbereiten
        folder = os.path.dirname(win.library[0])
        win.navigate(folder, Gtk.StackTransitionType.NONE)
        k = len(win.flow.get_children())
        info = picker.folder_info(folder, 64, 40)
        out("OK" if k and info[0] else "FAIL",
            f"Hintergrund-Auswahl: Ordner öffnen ({k} Einträge in {os.path.basename(folder)})")
    win.pool.shutdown(wait=False)
except Exception as e:
    out("FAIL", f"Hintergrund-Auswahl: {type(e).__name__}: {e}")

# Bildschirme: Anordnungslogik ohne Sway prüfen
try:
    disp = load("displays", os.path.join(S, "displays.py"))
    def fake(name, w, h, x, scale=1.0, transform="normal"):
        return disp.Output({"name": name, "make": "Test", "model": name, "serial": "1", "active": True,
                            "modes": [{"width": w, "height": h, "refresh": 60000}],
                            "current_mode": {"width": w, "height": h, "refresh": 60000},
                            "rect": {"x": x, "y": 0}, "scale": scale, "transform": transform})
    a, b = fake("eDP-1", 2560, 1600, 0, 1.5), fake("DP-1", 1920, 1080, 500)
    assert a.logical() == (1706, 1066), a.logical()
    outs = [a, b]
    disp.snap(outs, b)
    disp.normalize(outs)
    assert not disp.overlaps(a, b) and disp.touches(a, b), (b.x, b.y)
    a.scale = 1.0
    disp.tidy(outs, a)
    assert not disp.overlaps(a, b) and disp.touches(a, b), (b.x, b.y)
    out("OK", "Bildschirme: Einrasten und Skalieren ordnen korrekt an")
except Exception as e:
    out("FAIL", f"Bildschirme: Anordnungslogik: {type(e).__name__}: {e}")

# Menüfenster (Tastenkürzel, Fenster, Einstellungen …): Stylesheet, Aufbau,
# Spaltenbreiten und Filter – ohne es anzuzeigen
try:
    menu = load("menu", os.path.join(S, "menu.py"))
    rows = menu.parse_rows("Super + Enter\tTerminal\nSuper + Q\tFenster schließen\0icon\x1fwindow-close\n"
                           "Einstellungen\0icon\x1fpreferences-system\n")
    assert [r[0] for r in rows] == [["Super + Enter", "Terminal"], ["Super + Q", "Fenster schließen"],
                                    ["Einstellungen"]], rows
    win = menu.build(menu.parse_args(["-p", "Test", "-a", "1"]), rows)
    out("OK", "Menüfenster: Stylesheet gültig, Fenster lässt sich aufbauen")
    firsts = [g for k, g in win.groups.items() if k[0] == "first"]
    assert firsts and len(firsts[0].get_widgets()) == 2, "erste Spalte nicht in einer Breitengruppe"
    out("OK", "Menüfenster: Spalten haben in allen Zeilen dieselbe Breite (SizeGroup)")
    win.entry.set_text("schließen")
    assert [r.index for r in win.visible] == [1], [r.index for r in win.visible]
    out("OK", "Menüfenster: Suche filtert")
except Exception as e:
    out("FAIL", f"Menüfenster: {type(e).__name__}: {e}")
PY
  while IFS=$'\t' read -r kind msg; do
    case $kind in OK) ok "$msg" ;; WARN) hint "$msg" ;; FAIL) bad "$msg" ;; esac
  done < <(python3 "$TMP/gtk_check.py" "$S" 2>"$TMP/gtk_err")
  grep -qE 'Traceback|Error' "$TMP/gtk_err" && { hint "Python-Meldungen:"; tail -n 4 "$TMP/gtk_err" | while read -r l; do info "$l"; done; }
fi

# ── Tastenkürzel-Übersicht: zwei Spalten für das Menüfenster? ───────
# python3 wird durch einen Platzhalter ersetzt, der nur den Aufruf von menu.py
# abfängt (kein Fenster); alles andere geht an das echte python3.
section "Tastenkürzel-Übersicht"
mkdir -p "$TMP/stub"
real_py=$(command -v python3)
cat > "$TMP/stub/python3" <<EOF
#!/bin/sh
case "\$1" in
  *menu.py) cat > "\$CAPTURE"; exit 1 ;;
esac
exec "$real_py" "\$@"
EOF
chmod +x "$TMP/stub/python3"
if [[ -f $S/keybindings.sh ]]; then
  CAPTURE="$TMP/keys" PATH="$TMP/stub:$PATH" bash "$S/keybindings.sh" >/dev/null 2>&1
  if [[ -s $TMP/keys ]]; then
    n=$(wc -l < "$TMP/keys")
    broken=$(awk -F'\t' 'NF != 2 || $1 == "" || $2 == ""' "$TMP/keys" | wc -l)
    if (( broken == 0 )); then
      ok "$n Kürzel, je Zeile Taste und Beschreibung als eigene Spalte"
    else
      bad "$broken Zeilen der Kürzel-Übersicht ohne zwei Spalten (Taste<TAB>Beschreibung)"
    fi
  else
    bad "keybindings.sh lieferte keine Einträge"
  fi
fi

# ── Laufende Dienste (nur in der Sitzung) ───────────────────────────
section "Laufende Dienste"
if (( ! IN_SWAY )); then
  info "übersprungen (nicht in Sway)"
else
  ewwc=("$eww_bin" -c "$E")
  if "${ewwc[@]}" ping >/dev/null 2>&1; then
    ok "eww-Daemon läuft"
    nout=$(swaymsg -t get_outputs -r | jq '[.[] | select(.active)] | length')
    nbar=$("${ewwc[@]}" active-windows 2>/dev/null | grep -c '^bar_')
    if [[ -f $RUNTIME/bar-hidden ]]; then hint "Menüleiste ist ausgeblendet (Super+Strg+B)"
    elif (( nbar == nout )); then ok "Menüleiste auf allen $nout Bildschirm(en)"
    else bad "Menüleisten: $nbar offen, $nout Bildschirm(e) aktiv"; fi
    [[ $("${ewwc[@]}" get wsjson 2>/dev/null) == \[* ]] && ok "Menüleiste erhält Arbeitsflächen" || bad "Menüleiste erhält keine Arbeitsflächen (workspaces.sh)"
  else
    bad "eww-Daemon läuft nicht (Super+Shift+B startet die Menüleiste)"
  fi
  proc "monitor-watch.sh" && ok "Bildschirm-Überwachung (monitor-watch.sh)" || bad "monitor-watch.sh läuft nicht – Leisten passen sich nicht an"
  pgrep -u "$USER" -x swaybg >/dev/null && ok "Hintergrundbild (swaybg)" || bad "swaybg läuft nicht"
  cur=$(cat "$SETTINGS/current-wallpaper" 2>/dev/null)
  [[ -f $cur ]] && ok "Aktuelles Hintergrundbild: ${cur/#$HOME/\~}" || hint "Kein aktuelles Hintergrundbild gespeichert"
  pgrep -u "$USER" -x swayidle >/dev/null && ok "Bildschirmsperre (swayidle)" || bad "swayidle läuft nicht – keine automatische Sperre"
  if have kanshi; then pgrep -u "$USER" -x kanshi >/dev/null && ok "Bildschirmprofile (kanshi)" || bad "kanshi läuft nicht"; fi
  pgrep -u "$USER" -x dunst >/dev/null && ok "dunst läuft" || bad "dunst läuft nicht"
  srv=$(busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
          org.freedesktop.Notifications GetServerInformation 2>/dev/null | awk '{print $2}' | tr -d '"')
  [[ $srv == dunst ]] && ok "Mitteilungsdienst ist dunst" || bad "Mitteilungsdienst ist „${srv:-keiner}“ statt dunst"
  if have xsettingsd && [[ -n ${DISPLAY:-} ]]; then
    proc "xsettingsd -c $SETTINGS/xsettingsd.conf" && ok "xsettingsd (GTK-Einstellungen für X-Programme)" || hint "xsettingsd läuft nicht"
  fi
  if have cliphist; then proc "wl-paste --type text --watch cliphist" && ok "Zwischenablage-Verlauf läuft" || bad "Zwischenablage-Verlauf läuft nicht"
  elif have clipman; then proc "wl-paste.*clipman" && ok "Zwischenablage-Verlauf läuft" || bad "Zwischenablage-Verlauf läuft nicht"; fi
  if [[ ${DCONF_PROFILE:-} == *i3-apple* ]] && have gsettings; then
    t=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
    [[ $t == *WhiteSur* ]] && ok "GTK-Theme der Sitzung: $t" || hint "GTK-Theme der Sitzung: $t (theme.sh apply setzt WhiteSur)"
    t=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)
    [[ $t == *WhiteSur* ]] && ok "Symbol-Theme der Sitzung (Apps): $t" \
      || hint "Symbol-Theme der Sitzung ist $t statt WhiteSur – Apps zeigen andere Symbole (sway/install.sh --config-only, dann neu anmelden)"
  fi
  if systemctl --user show-environment 2>/dev/null | grep -q '^SWAYSOCK='; then
    ok "Umgebung an systemd/D-Bus weitergegeben (Bildschirmfreigabe, Portale)"
  else
    hint "Umgebung nicht an systemd weitergegeben (andere grafische Sitzung aktiv?) – Bildschirmfreigabe evtl. eingeschränkt"
  fi
  if [[ -s $SW/fx.conf ]]; then
    ns=$(swaymsg -t get_outputs -r | jq -r '[.[].layer_shell_surfaces[]?.namespace] | unique | join(", ")' 2>/dev/null)
    [[ -n $ns ]] && info "Layer-Shell-Flächen: $ns"
  fi
  if [[ -f $RUNTIME/services.log ]]; then
    info "Letzte Einträge aus $RUNTIME/services.log:"
    tail -n 12 "$RUNTIME/services.log" | while IFS= read -r l; do info "  $l"; done
  else
    hint "Kein Dienste-Protokoll – services.sh lief in dieser Sitzung noch nicht (Super+Shift+R)"
  fi
  n=$(python3 "$S/displays.py" profiles 2>/dev/null | grep -c .)
  ok "Bildschirm-Werkzeug antwortet ($n gespeicherte(s) Profil(e))"
  w=$(bash "$S/wallpaper.sh" list 2>/dev/null | grep -c .)
  (( w > 0 )) && ok "$w Hintergrundbild(er) in der Bibliothek" || hint "Keine Hintergrundbilder gefunden (~/.config/i3-apple/wallpapers)"
fi

# ── Andere Desktops unberührt? ──────────────────────────────────────
section "GNOME/Plasma unberührt"
g=$([[ -f $DATA/dbus-1/services/org.freedesktop.Notifications.i3-apple.service ]] && echo 1)
[[ -n $g ]] && ok "Mitteilungs-Weiche: dunst startet nur in Sway" || hint "Mitteilungs-Weiche fehlt – dunst könnte in Plasma/GNOME starten"
if have gsettings; then
  t=$(env -u DCONF_PROFILE gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
  if [[ $t == *WhiteSur* ]]; then
    hint "Normales GTK-Theme (das GNOME/Plasma nutzen) ist $t – gesetzt vom i3-Installer oder einer frühen Sway-Version"
    info "Zurücksetzen (nur die von i3-apple gesetzten Werte):"
    info "  for k in gtk-theme icon-theme cursor-theme cursor-size font-name color-scheme; do env -u DCONF_PROFILE gsettings reset org.gnome.desktop.interface \$k; done"
  else
    ok "Normales GTK-Theme (GNOME/Plasma) unverändert: ${t:-?}"
  fi
fi
bad_auto=0
for f in "$CFG"/autostart/i3apple-sway-*.desktop; do
  [[ -f $f ]] || continue
  grep -qx 'OnlyShowIn=sway;' "$f" || { bad "Autostart-Eintrag ohne OnlyShowIn=sway: ${f##*/}"; bad_auto=1; }
done
(( bad_auto )) || ok "Sway-Autostart-Einträge gelten nur für Sway"
[[ -f $CFG/gtk-4.0/gtk.css ]] && info "Hinweis: ~/.config/gtk-4.0/gtk.css existiert (nicht vom Sway-Installer)"

# ── Fenster kurz öffnen (--gui) ─────────────────────────────────────
if (( GUI )); then
  section "Fenster öffnen (--gui)"
  if (( ! IN_SWAY )); then
    info "übersprungen (nicht in Sway)"
  else
    for t in "wallpaper-picker.py:Hintergrund-Auswahl:i3apple-wallpaper" "displays.py:Bildschirme:i3apple-displays"; do
      IFS=: read -r file label appid <<<"$t"
      timeout 6 python3 "$S/$file" >/dev/null 2>"$TMP/gui_err" &
      pid=$!
      found=0
      for _ in $(seq 25); do
        sleep 0.2
        if swaymsg -t get_tree -r | jq -e --arg a "$appid" '[.. | objects | select(.app_id? == $a)] | length > 0' >/dev/null; then
          found=1; break
        fi
        kill -0 "$pid" 2>/dev/null || break
      done
      if (( found )); then ok "$label: Fenster erscheint"
      else bad "$label: kein Fenster"; tail -n 3 "$TMP/gui_err" | while read -r l; do info "$l"; done; fi
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    done
    notify-send -a "i3-apple Test" "Testmitteilung" "Wenn du das oben rechts siehst, funktionieren Mitteilungen." \
      && ok "Testmitteilung gesendet (sollte oben rechts erscheinen)" || bad "Testmitteilung fehlgeschlagen"
  fi
fi

# ── Ergebnis ────────────────────────────────────────────────────────
printf '\n\033[1mErgebnis:\033[0m \033[32m%d in Ordnung\033[0m · \033[33m%d Hinweise\033[0m · \033[31m%d Fehler\033[0m\n' "$PASS" "$WARN" "$FAIL"
(( FAIL )) && echo "Fehlende Pakete/Dateien: sway/install.sh (oder --config-only für die Konfiguration) erneut ausführen."
exit "$FAIL"
