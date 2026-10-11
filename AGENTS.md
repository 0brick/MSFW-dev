# AGENTS.md – i3-apple · Sway-Variante

Leitfaden für KI-Agenten. Er erklärt Aufbau, Zusammenhänge und Regeln dieses Ordners, damit du
gezielt die richtigen Dateien öffnest, statt alles zu lesen. Für Endnutzer gibt es `README.md`.
Stand: Oktober 2026. Wenn du Abläufe, Dateien oder Regeln änderst, passe dieses Dokument mit an.

---

## 1. Worum es geht

Eine Arbeitsumgebung im macOS-Stil für **SwayFX (Wayland)**. Sie ist **eigenständig**: Alles, was
installiert wird, liegt unter `sway/`. Die i3-Variante im Elternordner (`../`) spielt keine Rolle;
nichts wird von dort gelesen oder kopiert. Bestandteile:

- **SwayFX** als Compositor (Pflicht, siehe §5.9), gestartet über die eigene Anmeldesitzung
  „Sway (i3-apple)“.
- **eww** als Menüleiste mit Popups (WLAN, Bluetooth, Ton, Batterie, Kalender, Hintergrund-Apps).
- **rofi** für Spotlight-Launcher und alle Menüs; **dunst** für Mitteilungen.
- **Python/GTK3-Fenster** für die Hintergrundbild-Auswahl und die Bildschirmanordnung.
- **Bash-Skripte** für alles Übrige.

Zielsysteme: KDE neon, Kubuntu/Ubuntu und Debian (apt). Alle Kommentare, Meldungen und
Oberflächentexte sind **deutsch**; neuer Code folgt dem.

**Leitprinzip:** GNOME, KDE Plasma und andere Sitzungen dürfen nie verändert werden. Alles läuft in
eigenen Ordnern, mit eigener dconf-Datenbank und eigenen Konfigurationen (siehe §2).

---

## 2. Regeln, die du nie brechen darfst

1. **Andere Desktops nicht anfassen.** Tabu sind `~/.config/{gtk-3.0,gtk-4.0,rofi,dunst,kitty}`,
   `kdeglobals`, der Standard-Cursor und die normalen gsettings. GTK-Einstellungen der Sitzung
   kommen nur in die eigene dconf-Datenbank: `DCONF_PROFILE` → `~/.config/dconf/i3apple-sway`.
   `theme.sh` schreibt gsettings nur, wenn `DCONF_PROFILE` „i3-apple“ enthält.
2. **Pakete nie entfernen.** Der Installer simuliert jedes Paket vorher, installiert mit
   `apt-get --no-remove --no-install-recommends` und nimmt nichts, was ein anderes Paket schon
   bereitstellt. Ein Beispiel ist `neon-adwaita` auf KDE neon: `adwaita-icon-theme` zu verlangen,
   würde es entfernen.
3. **Eigene Einstellungen der Nutzer bleiben erhalten.**
   - `merge_tree` in `install.sh` merkt sich Prüfsummen. Was der Nutzer geändert hat, wird nicht
     überschrieben. Haben er und das Repo dieselbe Datei geändert, wird seine Fassung nach
     `~/.config/i3-apple/lokale-aenderungen/<TS>/` gesichert.
   - Dateien in `~/.config/i3-apple/` legt der Installer nur an, wenn sie fehlen. Ausnahmen sind
     `env-sway.sh` und `dconf-profile`; auch sie laufen über `merge_tree`.
4. **Sperr-Dateideskriptor schließen.**
   - Drei Skripte halten während ihres Laufs eine `flock` auf **fd 9**: `services.sh`
     (`services.lock`), `launch-bars.sh` (`launch.lock`) und `popup.sh` (`popup.lock`).
   - Jeder Prozess, den sie im Hintergrund starten, braucht `9>&-`. Sonst erbt er die Sperre, und
     alle späteren Läufe hängen.
   - `monitor-watch.sh` macht dasselbe mit fd 8.
5. **Hintergrundprozesse ablösen.** GUI-Programme und Dienste startest du mit
   `setsid -f CMD >/dev/null 2>&1 </dev/null`. Im rofi-Skriptmodus ist das Pflicht, weil rofi sonst
   wartet.
6. **Sway nur über `scripts/reload.sh` neu laden.** Ein nacktes `swaymsg reload` setzt
   Bildschirmanordnung und Skalierung zurück (§5.3).
7. **Keine fremden Daten in Shell-Befehle der Leiste.** WLAN-Netze werden deshalb über einen Index
   angesprochen (`wifi.sh connect-index N`), nie über ihre SSID.
8. **Repo-Pfade und installierte Pfade unterscheiden.** Die Skripte rufen sich gegenseitig über
   installierte Pfade auf (`~/.config/sway/...`), nicht über Pfade im Repo. Änderungen wirken erst
   nach `sway/install.sh --config-only`.

---

## 3. Ordnerstruktur: Repo → installierter Ort

```
sway/
├── install.sh            Installer (Pakete, eww/rofi bauen, Themes, Konfiguration, Sitzung, Sicherung)
├── test.sh               Selbsttest, ändert nichts (Exit-Code = Anzahl Fehler)
├── README.md             Nutzerdoku     · AGENTS.md (diese Datei) · CLAUDE.md (verweist hierher)
├── home/
│   ├── env-sway.sh          → ~/.config/i3-apple/env-sway.sh   Umgebung der Sitzung
│   ├── sway-apple-session   → /usr/local/bin/ (root)           lädt env-sway.sh, startet sway, räumt auf
│   ├── sway-apple.desktop   → /usr/share/wayland-sessions/ (root)
│   ├── notifications-activate → ~/.local/share/i3-apple/       D-Bus-Weiche: dunst nur in Sway
│   └── favorites, input, xsettingsd.conf → ~/.config/i3-apple/  Vorlagen, nur wenn sie fehlen
└── config/sway/          → ~/.config/sway/   (komplett, über merge_tree)
    ├── config               Sway-Konfiguration (Kürzel, Regeln, Autostart)
    ├── fx-effects.conf      SwayFX-Effekte → wird zu fx.conf kopiert
    ├── fx-animations.conf   animation_duration_ms → nur bei SwayFX ≥ 0.6 an fx.conf angehängt
    ├── bin/rofi             rofi-Wrapper (erzwingt ~/.config/sway/rofi/config.rasi), steht vorn im PATH
    ├── rofi/                config.rasi (@SWAY@ ersetzt der Installer), spotlight.rasi
    ├── dunst/dunstrc        Mitteilungen
    ├── kitty/               eigene kitty-Fassung: kitty.conf, colors-{dark,light}.conf (theme.conf schreibt theme.sh)
    ├── scripts/             alle Sitzungs-Skripte (§6)
    └── eww/
        ├── eww.yuck         Leiste + Popups (@EWW@ ersetzt der Installer durch den absoluten Pfad)
        ├── eww.scss         gesamter Stil der Leiste und Popups
        └── scripts/         alle Leisten-Skripte (inkl. battery, bluetooth, clock, dnd, volume, wifi)
```

**Nichts kommt von außerhalb von `sway/`.** `build_sway_tree` kopiert nur `config/sway/` und ersetzt
die Platzhalter `@EWW@` (eww.yuck) und `@SWAY@` (rofi/config.rasi). Die Vorlagen in `home/` kopiert
`deploy`/`setup_session`. `$ROOT`/`../config` darf nicht wieder eingeführt werden.

kitty: `build_sway_tree`
setzt JetBrains Mono, wenn SF Mono fehlt, und ab kitty 0.36 (`kitty_at_least`) ein weiches Blinken.
`kitty.conf` lädt `colors-dark.conf`, dann `globinclude theme.conf` (von `theme.sh`/`deploy` erzeugt,
nicht im Repo) und zuletzt `globinclude eigene.conf` (Nutzer). `globinclude` ist bei fehlender Datei
still. Neue Optionen nur so wählen, dass ältere kitty-Versionen (Debian 12: 0.26) sie als
*unbekannten Schlüssel* still überspringen. Ein *ungültiger Wert* löst dagegen einen Fehlerdialog aus.

**Persistente Nutzerdaten** in `~/.config/i3-apple/` (der Ordner heißt nach dem Projekt):

- **Sitzung und Eingabe:** `env-sway.sh`, `dconf-profile`, `sway-user.conf` (eigene Sway-Befehle,
  wird zuletzt geladen), `input` (Touchpad/Tastatur), `mode` (dark/light), `xsettingsd.conf`.
- **Launcher und Autostart:** `favorites`, `search-url`, `autostart-disabled-sway`.
- **Bildschirme:** `display-profiles.json`.
- **Hintergrundbild:** `current-wallpaper`, `wallpaper-dirs`, `wallpapers/`.
- **Menüleiste:** `bat_show_pct`, `xembed-tray` (leere Datei: alte XEmbed-Tray-Symbole über
  xembedsniproxy einschalten, siehe §4.2).

**Weitere installierte Orte:**

- `~/.local/share/icons/i3apple-sway-bar{,-fallback}`: Symbol-Theme der Leiste (§5.2).
- `~/.local/share/i3-apple/rofi-wayland/`: selbst gebautes rofi.
- `~/.local/share/i3-apple/swayfx-<tag>/` mit dem Verweis `swayfx`: selbst gebautes SwayFX samt
  scenefx (§5.9). Das Quellcode-Repo liegt in `~/.cache/i3-apple/{swayfx,scenefx}-src`, das
  Protokoll in `~/.cache/i3-apple/swayfx-build.log`.
- `~/.local/bin/eww`: eww mit X11 und Wayland.
- `~/.config/kanshi/config`: erzeugt von `displays.py`.
- `~/.local/share/dbus-1/services/org.freedesktop.Notifications.i3-apple.service`.

---

## 4. Lebenszyklus

### 4.1 Installation (`install.sh`)
Ablauf:

1. Sicherung erstellen.
2. Optional: `install_packages`, `build_eww`, `build_rofi`, `install_themes`, `install_apps`,
   `install_zed`. Diese Schritte entfallen mit `--config-only`.
   **`build_swayfx` läuft immer** (auch mit `--config-only`; ist SwayFX da, dauert es nur einen
   `sway --version`). Scheitert es, bricht der Installer **vor** `deploy` mit Exit-Code 1 ab.
   Build-Pakete dafür installiert `apt_install_extra` auch mit `--config-only` (Schalter
   `ALLOW_APT`); nur `--no-packages` verbietet apt ganz.
3. `deploy`: `build_sway_tree` baut den Zielbaum in einem leeren Ordner zusammen, `merge_tree`
   spielt ihn nach `~/.config/sway` ein.
4. `setup_session`:
   - `env-sway.sh` und `dconf-profile` einspielen;
   - `seed_dconf` und `icon_fallbacks`;
   - **`bar_icons`**;
   - `favorites` und `input` anlegen, falls sie fehlen;
   - Sitzungsdateien (mit sudo) und die D-Bus-Weiche für Mitteilungen;
   - kanshi-Konfiguration und Standard-Hintergrundbild.
5. Läuft Sway gerade, folgen `displays.py remember` und `reload.sh`.

Weitere Optionen: `--backup-only`, `--restore [ARCHIV]`, `--no-backup`, `--backup-dir=`. Was
gesichert wird, steht in `backup_paths()`. Neue Orte, die der Installer anlegt, gehören dort hinein.

### 4.2 Anmeldung und Sitzungsstart
1. **`sway-apple-session`** lädt `env-sway.sh` und startet `sway`. Danach entfernt es die
   exportierten Variablen aus systemd, falls `$RUNTIME/env-exported` existiert.
2. **`env-sway.sh`** setzt die Umgebung:
   - `XDG_CURRENT_DESKTOP=sway` und `DCONF_PROFILE`;
   - `KITTY_CONFIG_DIRECTORY`, Qt-Variablen und die Wayland-Variablen für Firefox, Qt und Electron;
   - `PATH` mit `~/.config/sway/bin` vorn und `~/.local/bin`;
   - `~/.local/share/i3-apple/swayfx/bin` ganz vorn, aber nur, wenn `sway --version` dort noch
     läuft. So startet `sway-apple-session` das selbst gebaute SwayFX; die Datei selbst bleibt
     unverändert.
   - schreibt `fx.conf`: Kopie von `fx-effects.conf` bei SwayFX, sonst leer. Enthält das Programm
     den String `animation_duration_ms` (SwayFX ≥ 0.6), wird `fx-animations.conf` angehängt.
3. **Sway-`config`** startet:
   - `exec scripts/autostart.sh`, einmal pro Sitzung. Es gibt die Umgebung an D-Bus/systemd weiter,
     aber nur, wenn keine andere grafische Sitzung läuft. Die eigene Sitzung erkennt es über
     `XDG_SESSION_ID` oder `/proc/self/sessionid`; Sitzungen im Zustand `closing` zählen nicht.
     Außerdem baut es `kbuildsycoca6` neu und startet die XDG-Autostart-Einträge über `dex`.
     Die Bildschirme stellt allein `services.sh` wieder her.
   - `exec_always`, also auch bei jedem Neuladen: `services.sh`, `eww/scripts/launch-bars.sh`,
     `input.sh`, `wallpaper.sh`.
4. **`services.sh`** startet nur, was fehlt. Es protokolliert nach `$RUNTIME/services.log`.
   - Bildschirme: `displays.py apply-snapshot`, ohne Snapshot `restore`.
   - Dienste: kanshi, xsettingsd (nur mit `DISPLAY`), dunst, polkit-Agent, cliphist/clipman,
     swayidle und `monitor-watch.sh`.
   - xembedsniproxy nur, wenn `~/.config/i3-apple/xembed-tray` existiert. Sonst beendet es einen
     laufenden mit dem eigenen `SWAYSOCK`. Grund: Es legt je Symbol ein schwarzes
     Override-Redirect-Fenster bei 0,0 an, das nur KWin per Deckkraft versteckt. In Sway liegt es
     als schwarzes Quadrat über der linken Ecke der Leiste.
   - Ausgeschaltete Effekte bleiben aus.
   - Einmal pro Sitzung, mit Markierung `…-<Sway-Socket>`: `theme.sh apply` und `bar-icons.py`.
5. **`launch-bars.sh`** sorgt dafür, dass das Symbol-Theme da ist, und startet bei Bedarf den
   eww-Daemon. Dann schließt es alles, schreibt `$RUNTIME/monitors` und öffnet je Bildschirm
   `bar --id bar_<n> --screen <n>`.

### 4.3 Neu laden (Super+Shift+R)
1. `reload.sh` sichert den Zustand mit `displays.py snapshot $RUNTIME/outputs-before-reload.json`
   und ruft `swaymsg reload` auf.
2. Danach laufen alle `exec_always`-Skripte erneut. `services.sh` spielt den Snapshot zurück
   (`apply-snapshot` löscht die Datei; Snapshots älter als 600 s werden durch `restore` ersetzt).

### 4.4 Bildschirm-Änderungen zur Laufzeit
- **Anstecken:** kanshi wendet das passende Profil an.
- **Leisten:** `monitor-watch.sh` abonniert `output`-Ereignisse, wartet 1,5 s Ruhe ab und baut dann
  mit `launch-bars.sh` alle Leisten neu auf.

---

## 5. Subsysteme

### 5.1 Menüleiste (eww)
- **Fenster** in `eww.yuck`:
  - `bar [output]`: Ebene `fg`, `:exclusive true` (Sway reserviert 32 px), Namespace `eww-bar`.
  - `closer`: unsichtbare Vollbild-Klickfläche auf Ebene `fg`, Namespace `eww-closer`. Ein Klick
    schließt alle Popups.
  - Popups `calendar|wifi|bluetooth|volume|battery|apps`: Ebene `overlay`, Namespace `eww-popup`.
    Popups müssen über der Klickfläche liegen, sonst schließt ein Klick ins Popup dieses selbst.
- **Variablen:**
  - `deflisten`: `wsjson` (workspaces.sh), `focused` (focused.sh), `volume` (`volume.sh listen`).
  - `defpoll`: `clock`, `wifi`, `bt`, `battery`, `recording` (`../scripts/record.sh status`).
  - Popup-Daten laufen nur mit `:run-while {popup == "<name>"}`.
  - `defvar`: `popup`, `bat_show_pct`.
- **Daten zurück in die Leiste:** Die Skripte schreiben direkt mit `eww_ update var=JSON`
  (`lib.sh`), etwa nach einem Klick.
- **`eww/scripts/lib.sh`** (per `source` in allen Leisten-Skripten) stellt bereit:
  - `EWW_DIR`, `SETTINGS`, `RUNTIME=$XDG_RUNTIME_DIR/sway-apple`, `SESSION_LABEL=Sway`;
  - `eww_` (eww mit `-c $EWW_DIR`), `notify TAG TITEL [TEXT]`, `popup_open NAME` und
    `screen_of AUSGANG`.
  - Die Leisten-Skripte erwarten genau diese Namen. Benenne sie nicht um.
- **`popup.sh`:**
  - Aufruf: `popup.sh <name> [output]` schaltet um, `close` schließt alles, `launch <network|…|autostart>`
    schließt und startet eine Einstellungs-App.
  - Zustand in `$RUNTIME/popup` als `name@output`.
  - Ablauf: alles schließen; war es derselbe Popup, endet der Aufruf hier (zweiter Klick schließt).
    Sonst `eww update popup=…`, dann `closer_<s>` auf **jedem** Bildschirm öffnen, den Zustand
    eintragen und das Popup auf dem Bildschirm des Ausgangs öffnen. Scheitert das Öffnen, wird
    alles wieder geschlossen.
  - Alles, was `popup.sh` startet, bekommt `9>&-`; auch `eww open`, weil das den Daemon starten
    kann.
- **Bildschirm-Zuordnung:**
  - eww zählt Bildschirme wie GTK, Sway hat Ausgangsnamen.
  - `gdk-monitors.py` gibt `index\tx\ty` aus; `launch-bars.sh` ordnet das über die Position den
    Sway-Ausgängen zu und schreibt das Ergebnis nach `$RUNTIME/monitors` (`ausgang\tgdk-index`).
  - Jeder Index wird nur einmal vergeben. Ausgänge ohne Treffer bekommen freie Indizes in Sways
    Reihenfolge.
- **Leisten-Skripte** (alle ohne Unterbefehle):

  | Skript | Ausgabe |
  |---|---|
  | `workspaces.sh` | Abonniert `workspace,output` und gibt `[{id,num,name,focused,visible,urgent,output}]` aus. `goto <id>` wechselt über die Knoten-ID, auch zu benannten Arbeitsflächen ohne Nummer. |
  | `focused.sh` | Abonniert `window,workspace` und gibt `{output,title,app}` aus. |
  | `apps.sh` | `list` gibt `[{id,ws,app,title}]` aus (höchstens 14); außerdem `focus <con_id>` und `close <con_id>`. |

  Der App-Name kommt aus `app_id`, sonst aus der X11-Klasse. Eine leere `app_id` zählt als
  fehlend; jqs `//` allein greift nur bei `null`. Dasselbe Muster nutzen `window.sh` und
  `windows.sh`.

- **JSON der Status-Skripte:**

  | Skript | Ausgabe |
  |---|---|
  | `battery.sh status` | `{available,capacity,state,plugged,icon}` |
  | `wifi.sh status` | `{enabled,connected,wired,ssid,signal,icon,label}` |
  | `bluetooth.sh status` | `{available,powered,connected,icon,label}` |
  | `volume.sh status` | `{volume,muted,mic,mic_muted,icon,mic_icon}` |
  | `wifi.sh list` | `[{ssid,signal,secure,active,known,uuid,idx,icon}]`. Gespeicherte Profile werden über die SSID erkannt und über die UUID verbunden; der Profilname zählt nicht. |
  | `bluetooth.sh devices`, `volume.sh sinks`, `battery.sh profiles` / `details` | Popup-Daten. `bluetooth.sh` fragt bei BlueZ vor 5.65 jedes Gerät einzeln ab. |
  | `clock.sh bar` / `long` | reiner Text |
  | `dnd.sh status` | `true` oder `false` |

  Die Skripte liefern **Symbolnamen** (`*-symbolic`), nie Dateipfade.
- **Stil:**
  - Der gesamte Stil steht in **einer** Datei, `eww/eww.scss`. Sie ist fest auf Dunkel gestaltet
    und beginnt mit `* { all: unset; }`, gleich danach legt sie das Symbol-Theme fest (§5.2).
  - **Popups im Kontrollzentrum-Stil:** Die Bausteine `(header :title :subtitle …kinder)` und
    `(section :text)` stehen in `eww.yuck`; Listen und Regler liegen in `(box :class "card")`.
  - `.popup` hat `border-radius: 14px`, ebenso `corner_radius 14` bei `layer_effects "eww-popup"`
    in `fx-effects.conf`. Ändere beide Werte zusammen.
- **Animationen** (GTK3-CSS: `transition`, `@keyframes`/`animation`):
  - `.bar`, `.popup` und `tooltip` blenden beim Erzeugen ein. Hover-Flächen haben Übergänge; der
    Knopf von `toggle` gleitet über `margin-left` und bleibt darum immer `:halign "start"`.
  - **Keine Einblend-Animation an Elementen innerhalb von `(for …)`:** eww baut sie bei jeder
    Aktualisierung neu (WLAN-Liste alle 8 s), sie würden flackern. Ausnahme: Die aktive
    Arbeitsflächen-Pille (`ws-grow`) soll genau beim Neuaufbau nach einem Wechsel wachsen.
  - Fenster und Arbeitsflächen animiert SwayFX ab 0.6 selbst (`fx-animations.conf`, §5.9).
    Ältere Versionen und normales Sway können das nicht.
- **Leiste ausblenden:** `toggles.sh bar` setzt `$RUNTIME/bar-hidden`; `launch-bars.sh` endet dann
  gleich nach `close-all`.

### 5.2 Symbol-Theme der Menüleiste (`eww/scripts/bar-icons.py`)
**Problem, das es löst:** GTK nimmt das Symbol-Theme normalerweise aus gsettings/dconf der Sitzung.
Kommt dort kein WhiteSur an oder fehlen GNOME-Namen (KDE neon liefert nur ein leeres „Adwaita“),
zeigt GTK Platzhalter. Darum legt `eww.scss` die Leiste fest:
`* { -gtk-icon-theme: "i3apple-sway-bar"; }`.

- **`i3apple-sway-bar`** hat keine eigenen Grafiken. Es erbt in dieser Reihenfolge von
  `WhiteSur-dark, WhiteSur, Adwaita, breeze-dark, breeze, i3apple-sway-bar-fallback, hicolor`.
- **`i3apple-sway-bar-fallback/status/`** enthält nur Symlinks. Sie stehen für Namen, die kein
  anderes Theme der Kette hat, zum Beispiel `battery-level-50-symbolic.svg` → Breezes
  `battery-050.svg`. Weil die Endung `-symbolic` lautet, färbt GTK sie wie alle anderen ein.
- Die Symbolnamen und ihre Ersatznamen stehen in **`wanted()`**. **Ein neues Symbol in `eww.yuck`
  oder einem Leisten-Skript gehört auch dorthin.**
- **Aufrufe:**
  - `bar-icons.py` gleicht ab und ändert nur, was abweicht.
  - `bar-icons.py check` prüft nur.
  - Exit-Code: 0 = alles da, 1 = es fehlen Symbole, 2 = kein GTK.
- **Wer es aufruft:** `install.sh bar_icons`, `services.sh` (einmal pro Sitzung), `launch-bars.sh`
  (nur wenn `index.theme` fehlt) und `test.sh` (`check`).
- **Fallstricke:**
  - Ohne `Directories=` verwirft GTK ein Theme samt seinen `Inherits`.
  - Fehlt das Theme ganz, findet die Leiste **gar kein** Symbol. Deshalb prüft `launch-bars.sh`,
    ob es da ist.

### 5.3 Bildschirme (`scripts/displays.py`, `display-menu.sh`)
- **Kommandozeile:**
  - `quick extend-right|extend-left|extend-above|mirror|internal|external`
  - `profiles`, `save NAME`, `load NAME`, `restore`
  - `snapshot DATEI`, `apply-snapshot DATEI` (entfernt die Datei immer, auch eine kaputte)
  - `remember [--only-if-missing]`, `mirror-start`, `write-kanshi`
  - Ohne Argument öffnet sich das **GTK-Fenster** (app_id `i3apple-displays`, gegen doppelten
    Start gesperrt).
- **Klasse `Output`** liest `swaymsg -t get_outputs`. Erkannt wird ein Bildschirm an
  `criteria()` = „Hersteller Modell Seriennummer“. Für interne Panels und Geräte ohne Seriennummer
  steht dort der Anschlussname.
- **Profile** liegen in `display-profiles.json`: `{"profiles": {name: {"outputs": [state…]}}}`.
  - Je Kombination angeschlossener Bildschirme gibt es genau ein Profil
    (`profile_key` = sortierte criteria).
  - Jede `quick`-Aktion und jedes bestätigte „Anwenden“ speichert ein Profil automatisch.
  - Gehört ein Name schon zu einer anderen Kombination, bleibt deren Profil bestehen; das neue
    bekommt einen Zusatz wie „Büro (2)“. `upsert_profile` gibt den tatsächlichen Namen zurück.
  - `save_store` schreibt danach `~/.config/kanshi/config` neu und lädt kanshi neu. Eine fremde
    kanshi-Konfiguration wird vorher als `.bak-<TS>` gesichert.
  - Gespeichert wird nach `~/.config/i3-apple/`, fest wie in allen anderen Skripten. Nur die
    kanshi-Datei folgt `$XDG_CONFIG_HOME`, weil kanshi selbst dort liest.
- **Anordnungslogik** ist reine Funktion und wird in `test.sh` geprüft:
  - `snap` setzt Bildschirme lückenlos aneinander, `normalize` verschiebt alles auf 0,0, `tidy`
    rückt nach einer Größenänderung nach, `chain` reiht auf.
  - `apply_outputs` schickt alles in **einem** `swaymsg`-Aufruf, aktive Bildschirme zuerst, und
    weigert sich, wenn keiner aktiv bliebe.
- **Anwenden im GTK-Fenster:** Danach fragt ein Dialog 15 Sekunden lang „Beibehalten?“. Ohne
  Antwort stellt er die vorherigen Einstellungen wieder her.
- **Spiegeln:** Sway kann das nicht selbst; `wl-mirror --fullscreen` übernimmt.
  - Läuft beim Merken eines Profils ein wl-mirror, wird es mit `"mirror": true` gespeichert.
  - Solche kanshi-Profile bekommen `exec … displays.py mirror-start`. Alle anderen bekommen
    `exec pkill -x wl-mirror`, aber nur wenn es überhaupt ein Spiegel-Profil gibt.
  - `load` und `restore` starten das Spiegeln ebenfalls wieder.
- **`display-menu.sh`** (Super+P) ist das rofi-Schnellmenü. Den Hauptbildschirm bestimmt es nach
  derselben Regel wie `split_internal()`: das Laptop-Panel, sonst der erste Bildschirm nach Name.

### 5.4 Hintergrundbild (`scripts/wallpaper.sh`, `wallpaper-picker.py`)
- **`wallpaper.sh`:**
  - Ohne Argument stellt es `current-wallpaper` wieder her. Dieser Aufruf läuft bei jedem
    Neuladen (`exec_always`) und tut nichts, wenn swaybg schon das richtige Bild zeigt.
  - `set BILD`, `random`, `rotate` (alle 600 s), `select`, `list`, `dirs`, `add-dir ORDNER`
    (Ordner in `wallpaper-dirs` aufnehmen; für „Ordner hinzufügen …“ im Auswahlfenster).
  - Es läuft **ein** swaybg für alle Bildschirme. `start_bg` startet das neue (Bild oder
    `#farbe`), bevor das alte beendet wird, damit nichts flackert.
  - Danach beendet `start_bg` alle übrigen swaybg des Nutzers, auch nie vermerkte. Zustand in
    `$RUNTIME/swaybg.{pid,image}`.
- **Ordner:** `wallpapers/`, der Bilder-Ordner (`Hintergründe`, `Wallpapers`) und die gemerkten
  Ordner aus `wallpaper-dirs`.
- **`wallpaper-picker.py`** ist ein GTK-Fenster (app_id `i3apple-wallpaper`). Ohne python3-gi oder
  cairo fällt `select` auf ein rofi-Raster zurück.
  - **Aufbau:** Seitenleiste (`fill_places`: „Alle Bilder“ = `LIBRARY`, `wallpaper.sh dirs`, Bilder,
    persönlicher Ordner) und ein `Gtk.Stack` mit zwei `Page`s. Beim Ortswechsel wird die
    unsichtbare Seite gefüllt und hineingeschoben (`navigate` → `refresh(transition)`).
  - **Orte** sind `LIBRARY` (`None`) oder ein realpath. Ordner im Raster sind Kacheln
    (`folder_info`: Anzahl und erstes Bild als Vorschau) und öffnen sich per Klick. `history` und
    `go_back`/`go_up` übernehmen die Navigation.
  - **Suchfeld:** Es filtert den aktuellen Ort (`score`/`ranked`). Text mit `/`, `~` oder `.` ist
    Pfadmodus mit Tab-Vervollständigung (wie bisher).
  - **Hintergrundarbeit:** `want(key, fn, args, callback)` lädt Vorschauen und Ordner-Infos im
    Thread-Pool; `cancel_jobs` verwirft beim Ortswechsel, was noch nicht begonnen hat. Ergebnisse
    landen in `results`, auf Platte in `~/.cache/i3-apple/thumbs`. Frische Vorschauen blenden ein
    (`Thumb` per Tick-Callback).
  - Das CSS ist auf `.panel` beschränkt, damit der Ordner-Dialog normal aussieht. Der
    Panel-Radius (12 px) entspricht `corner_radius` in `fx-effects.conf`.
  - `test.sh` nutzt `CSS`, `Picker()`, `refresh()`, `flow`, `library`, `navigate`, `folder_info`,
    `load_thumb` und `pool`. Benenne sie nicht um.

### 5.5 Erscheinungsbild und GTK (`scripts/theme.sh`)
- `toggle|light|dark|menu|apply`. Es setzt `gtk-theme`, `icon-theme` und `color-scheme` in der
  **eigenen** dconf-Datenbank und passt `xsettingsd.conf` für X-Programme an.
- Mit `apply` setzt es Schrift, Cursor und Fensterknöpfe nur, solange dort noch nichts Eigenes
  eingetragen ist.
- Es schreibt `~/.config/sway/kitty/theme.conf` (`include colors-<mode>.conf`) und schickt laufenden
  kitty-Prozessen `SIGUSR1`, damit sie neu laden. Das passiert **nur ab kitty 0.28**; ältere
  Versionen würden an dem Signal beendet.
- Die Menüleiste hängt davon **nicht** ab (§5.2).

### 5.6 Eingabe (`scripts/input.sh`)
- Liest `~/.config/i3-apple/input` (`key=value`: tap, natural_scroll, disable_while_typing,
  mouse_natural_scroll, repeat_delay, repeat_rate, layout, variant, options).
- Das Tastaturlayout kommt aus dieser Datei, sonst aus `~/.config/kxkbrc`, sonst aus
  `/etc/default/keyboard`.
- Befehle, deren Schlüssel schon in `sway-user.conf` gesetzt ist, lässt es aus.

### 5.7 Launcher, Menüs, Fenster
- **`launcher.sh`** ist ein rofi-Skriptmodus.
  - Ohne `ROFI_RETV` startet es rofi.
  - Mit `ROFI_RETV=0` gibt es die Liste aus: Favoriten, Apps, `sys:*`-Aktionen und Dateien.
  - Mit `ROFI_RETV=1` führt es die Auswahl aus (`ROFI_INFO` = `app:` / `file:` / `sys:`).
  - Mit `ROFI_RETV=2` startet es eine Websuche.
- **`desktop-lib.sh`** (wird per source geladen):
  - `APP_DIRS`, `desktop_path`, `desktop_files`;
  - `desktop_parse [--all]` gibt `Name\tIcon\tPfad\tKeywords` aus. Felder sind nie leer, weil `read`
    mit Tab-IFS leere Felder zusammenzieht.
- **Weitere Menüs:**
  - `windows.sh`: Fensterwechsler über Sways IPC (Super+Tab).
  - `window.sh maximize|kill-app`: Maximieren als Markierung `_max_<id>`; schließt alle Fenster
    einer App.
  - `settings-menu.sh`: Einstellungs-Zentrale.
  - `settings-app.sh network|bluetooth|sound|power|system`: KDE-Modul → GNOME → GTK-Werkzeug;
    öffnet nur Fenster.
  - `powermenu.sh`.
  - `keybindings.sh`: Übersicht der Tastenkürzel, siehe §7.
- **Menüfenster `menu.py`** (GTK3, app_id `i3apple-menu`, schwebend per `for_window`) ersetzt
  `rofi -dmenu` in Kürzel-Übersicht, `windows.sh`, `autostart-manager.sh`, `settings-menu.sh`,
  `powermenu.sh`, `display-menu.sh`, `screenshot.sh gui` und `theme.sh menu`.
  - Muster: `printf 'Spalte1\tSpalte2\0icon\x1fname\n' | python3 …/menu.py -p PLATZHALTER
    [-m HINWEIS] [-w BREITE] [-l ZEILEN] [-a 1,3] [-f i|s]`. Exit 1 = abgebrochen.
  - Spalten trennt ein TAB. Je Spaltenposition eine `Gtk.SizeGroup`: erste und (ab drei Spalten)
    letzte Spalte so breit wie ihr längster Eintrag, dazwischen füllt und kürzt mit „…“.
  - Feste Listenhöhe (`ROW_H` passt zum CSS), damit das Fenster beim Filtern nicht springt.
    Ein Fokusverlust schließt das Fenster wie bei rofi.
  - Animation: `.panel` blendet ein, `.list` gleitet dazu (CSS-Keyframes); dazu kommt ab
    SwayFX 0.6 dessen Öffnen-Animation.
  - Ohne GTK oder bei einem Fehler im Aufbau startet es dasselbe Menü mit rofi (Fehler in
    `$RUNTIME/menu.log`). `test.sh` nutzt `parse_rows`, `parse_args`, `build`, `groups`,
    `visible` und `entry`; benenne sie nicht um.
- **rofi** bleibt für Spotlight (`launcher.sh`, Skriptmodus), Texteingaben (WLAN-Passwort,
  Profilname), Zwischenablage, Emoji und den Ersatz der Hintergrund-Auswahl. `rofi` ist dabei immer
  der Wrapper in `config/sway/bin/rofi`.

### 5.8 Bildschirmfoto, Aufnahme, Texterkennung, Sperre
- **`screenshot.sh gui|full|output|window|area`:**
  - Werkzeuge: grim, slurp und swappy.
  - Ziel: `Bilder/Bildschirmfotos/`; das Bild kommt zusätzlich in die Zwischenablage.
  - `gui` öffnet ein Auswahlmenü wie ⌘⇧5 am Mac.
- **`record.sh start <bereich|bildschirm> [ohne|system|mikro] | stop | toggle | status`:**
  - Nimmt mit wf-recorder auf; Zustand in `$RUNTIME/record.{pid,info,log}`.
  - `status` gibt `{"active":…,"time":"m:ss"}` aus. Die Leiste fragt das jede Sekunde ab;
    `record.sh` aktualisiert sie zusätzlich sofort.
- **`ocr.sh`:** Bereich auswählen, tesseract mit `deu+eng`, Text in die Zwischenablage.
- **`lock.sh`:** unscharfes Bildschirmfoto je Bildschirm, `swaylock -f`, dunst pausiert. swayidle
  sperrt nach 600 s und schaltet die Bildschirme nach 660 s aus; außerdem vor dem Ruhezustand.
- **Fingerabdruck (`fingerprint.sh`):** nutzt fprintd mit den schon eingerichteten Fingern (wie
  GDM).
  - `available`: Leser da, ein Finger in `fprintd-list`, swaylock ≥ 1.6. lock.sh merkt sich das
    30 min in `$RUNTIME/fingerprint.available` und fragt mit `timeout 2`, weil logind vor dem
    Ruhezustand nur kurz wartet.
  - Ist es nutzbar, schreibt lock.sh „Finger auflegen oder Passwort eingeben“ ins Sperrbild und
    startet nach `swaylock -f` die Schleife abgelöst.
  - Die Schleife ruft `fprintd-verify` immer wieder auf. Bei `verify-match` folgt
    `pkill -USR1 -x swaylock` (swaylock entsperrt daran). Wird mit Passwort entsperrt, beendet sie
    `fprintd-verify`, damit der Leser frei wird.
  - **Nie SIGUSR1 an swaylock vor 1.6 schicken:** Ältere werden daran beendet, und der Bildschirm
    bliebe gesperrt.

### 5.9 Mitteilungen, Autostart, Effekte
- **dunst** läuft mit `~/.config/sway/dunst/dunstrc`. `home/notifications-activate` sorgt dafür,
  dass D-Bus dunst nur in Sway startet; sonst reicht es an den Mitteilungsdienst des Desktops
  weiter. Die Zeile für `XDG_CURRENT_DESKTOP=i3` bleibt bewusst drin: Der D-Bus-Eintrag gilt für
  alle Sitzungen des Nutzers, ohne sie bekäme eine i3-Sitzung keinen dunst mehr (§2.1).
- **Autostart:**
  - Abschalten trägt die ID nur in `autostart-disabled-sway` ein.
  - Hinzugefügte Apps bekommen `~/.config/autostart/i3apple-sway-*.desktop` mit
    `OnlyShowIn=sway;`.
  - Fremde `.desktop`-Dateien werden nie bearbeitet (`autostart-manager.sh`).
- **`toggles.sh nightlight|animations|gamemode|bar`:** Merkzeichen liegen in `$RUNTIME`.
  - Ob das Nachtlicht an ist, liest es am eigenen gammastep-Prozess ab (PID und Prozessname),
    nicht am Merkzeichen.
  - `bar` schließt beim Ausblenden zuerst die Popups.
  - Im Spielmodus schaltet `animations` die Effekte erst wieder ein, wenn der Spielmodus endet.
  - `fx_off` schaltet die Effekte über swaymsg ab, steht `animation_duration_ms` in `fx.conf`, auch
    die Animationen. `services.sh` ruft es über `toggles.sh effects-off` auf, damit der Befehl nur
    an einer Stelle steht.
  - `fx_on` spielt `fx.conf` Zeile für Zeile erneut ein, darum muss dort jeder Befehl in einer
    eigenen Zeile stehen.
- **`fx-effects.conf`:** Ecken (12 px, `smart_corner_radius off`, also auch bei einem einzelnen
  Fenster), Schatten, Unschärfe und `layer_effects` für die Namespaces `eww-bar`, `eww-popup`,
  `rofi` und `notifications`.
- **SwayFX-Erkennung** (`env-sway.sh`, `install.sh is_swayfx`, `test.sh is_swayfx`):
  - Zuerst zählt das selbst gebaute SwayFX, sofern es startet (`swayfx_built_ok`).
  - Sonst das `sway` im PATH: `sway --version` enthält „swayfx“ **oder** das Programm enthält den
    String `corner_radius` (`grep -qa`). Manche Pakete melden sich als „sway version …“.
  - Ändere alle drei Stellen gemeinsam.
  - `deploy` entscheidet über `fx_wanted`: Läuft Sway, zählt das laufende Programm
    (`/proc/<pid>/exe`). Sonst würde das anschließende Neuladen in einem normalen Sway unbekannte
    Befehle melden, wenn SwayFX gerade erst gebaut wurde. `fx.conf` bleibt dann bis zur nächsten
    Anmeldung leer.
  - Ein leeres `fx.conf` gibt es sonst nur noch als Notbehelf in `env-sway.sh`, wenn der eigene
    Build nach einem System-Update nicht mehr startet. `test.sh` meldet fehlendes SwayFX als Fehler.
- **Animationen** (Fenster öffnen/schließen, verschieben, Arbeitsfläche wechseln) kann erst
  SwayFX ab 0.6 (`animation_duration_ms`, in `fx-animations.conf`). Erkannt wird das wie
  `corner_radius` am String im Programm (`fx_has_animations`). `deploy` hängt die Datei nur an,
  wenn das *laufende* Sway sie kennt (`fx_animations_wanted`).
- **SwayFX ist Pflicht** (`build_swayfx` in `install.sh`, läuft bei jedem Installer-Lauf). Gebaut
  wird, wenn weder ein startfähiger eigener Build noch ein System-SwayFX da ist, **oder** wenn
  das vorhandene keine Animationen kann.
  - Nachrüsten: `fx_prepare` (Pakete und Quellen), dann `fx_try 0.6`. Scheitert es, bleibt das
    vorhandene SwayFX (Rückgabe 0). Der Tag landet in
    `~/.cache/i3-apple/swayfx-animationen-fehlgeschlagen`; eine Woche lang wird nichts versucht,
    danach erst wieder bei einem neueren Tag.
  - Neubau ohne SwayFX: erst `fx_try 0.6`, dann `fx_try ""` (jede Version). `fx_tried` verhindert,
    dass dieselbe Kombination zweimal gebaut wird.
  - Zuerst installiert `apt_install_extra` alle Build-Pakete nach den Regeln aus §2.2, auch die
    für wlroots als Unterprojekt (libseat, libdisplay-info, liblcms2, libliftoff, xcb-…).
  - **1. Weg (System-wlroots):** `wlroots_candidates` listet die wlroots-Reihen, die als
    `-dev`-Paket verfügbar oder schon installiert sind, neueste zuerst. `fx_find_tag` sucht in
    blobless geklonten Repos den neuesten Tag, dessen `meson.build` `>=<reihe>.` verlangt (plus
    Merkmal „scenefx“, weil die Repos auch Sway-/wlroots-Tags enthalten). `fx_scenefx_tag` nimmt
    die scenefx-Reihe aus `dependency('scenefx-X.Y'` der SwayFX-Version, sonst ebenfalls über die
    wlroots-Reihe. `fx_install` baut dann scenefx und SwayFX nacheinander.
  - **2. Weg (eigenes wlroots):** die drei neuesten SwayFX-Tags; je Tag liest `fx_wlroots_series`
    die verlangte wlroots-Reihe, `git ls-remote` auf `WLROOTS_URL` liefert deren neuesten Tag.
    `fx_install … <wlroots-tag>` setzt `FX_SUBPROJECTS`, `fx_build` klont wlroots und scenefx nach
    `subprojects/` (nach `git clean -ffdx`; einfaches `-f` lässt verschachtelte Repos liegen),
    meson baut alles in einem Lauf. Dabei gilt `--wrap-mode=default`: Ist eine Systembibliothek
    zu alt (KDE neon: xkbcommon 1.6, wlroots will ≥ 1.8), lädt meson sie über die `.wrap`-Dateien
    von wlroots nach. Kommt so ein eigenes libxkbcommon mit, setzt `env-sway.sh`
    `XKB_CONFIG_ROOT`/`XLOCALEDIR` auf die Systemordner.
  - `fx_build` baut mit `--libdir=lib` und rpath `<prefix>/lib` nach `swayfx-<tag>`.
    meson-Optionen, die die Version nicht kennt, lässt es weg.
  - Erst nach erfolgreichem `sway --version` (Ausgabe im Protokoll) wird der Verweis `swayfx`
    umgesetzt; alte Versionsordner werden dann gelöscht.
  - `build_swayfx` gibt 1 zurück, wenn alles scheitert, und zeigt das Protokollende. Aufgerufen
    wird es als `if ! build_swayfx` – darin gilt **kein** `set -e`, jeder Schritt prüft selbst.
    Schleifenrümpfe, die aus `< <(…)` lesen, geben Unteraufrufen `</dev/null`.

---

## 6. Laufzeitdateien (`$XDG_RUNTIME_DIR/sway-apple/`)

| Datei | Wer schreibt / liest |
|---|---|
| `services.log` | services.sh, autostart.sh (erst nachsehen bei Problemen) |
| `services.lock`, `launch.lock`, `popup.lock`, `monitor-watch.lock` | flock (§2.4) |
| `monitors` | launch-bars.sh → popup.sh, `screen_of` |
| `popup` | popup.sh (`name@output`), lib.sh `popup_open` |
| `bar-hidden`, `no-effects`, `gamemode`, `nightlight` | toggles.sh |
| `theme-applied-<sock>`, `bar-icons-<sock>` | services.sh (einmal pro Sitzung) |
| `env-exported` | autostart.sh → sway-apple-session (Aufräumen beim Abmelden) |
| `outputs-before-reload.json` | reload.sh → services.sh |
| `swaybg.pid`, `swaybg.image`, `wallpaper-rotate.pid`, `wallpaper-picker.{lock,log}` | wallpaper* |
| `record.{pid,info,log}`, `gammastep.pid`, `wifi-list.json` | record.sh, toggles.sh, wifi.sh |
| `displays.{lock,log,out}`, `lock/` | displays.py, display-menu.sh, lock.sh |
| `menu.log` | menu.py (Fehler beim Aufbau → Ersatz mit rofi) |
| `fingerprint.{lock,log,out,available}` | fingerprint.sh, lock.sh |

---

## 7. Tastenkürzel (Auszug aus `config/sway/config`)

**Beschreibungen:** Eine Zeile `#: Beschreibung` **unmittelbar** über einem `bindsym` ist der Text
in der Übersicht (Super+Strg+K, `keybindings.sh`). Steht eine andere Zeile dazwischen, fehlt die
Beschreibung. `keybindings.sh` liest `~/.config/sway/config` und danach `sway-user.conf`.

| Kürzel | Aktion |
|---|---|
| Super+Leertaste / Super+Strg+Enter | `launcher.sh` |
| Super+Enter | kitty |
| Super+Tab | `windows.sh` |
| Super+P | `display-menu.sh` |
| Super+Strg+S / K / C / W / P / L | Einstellungen / Kürzel-Übersicht / Kalender-Popup / Hintergrund wählen / Power-Menü / Sperren |
| Super+Strg+B | Leiste ein/aus |
| Super+Shift+B | Leiste neu aufbauen |
| Super+Shift+R | `reload.sh` |
| Super+Shift+M | Hell/Dunkel |
| Super+Shift+W | zufälliger Hintergrund |
| Super+Shift+H | Nachtlicht |
| Super+Shift+A | Effekte ein/aus |
| Super+Alt+G | Spielmodus |
| Super+Druck | Bildschirmfoto-Menü |
| Super+Alt+R | Aufnahme starten/beenden |
| Super+Alt+A | Texterkennung (OCR) |
| Super+B / E / C / V | `run.sh browser` / `files` / `calculator` / `clipboard` |
| Super+Q | Fenster schließen |
| Super+Shift+Q | ganze App schließen |
| Super+M / F / T | maximieren / Vollbild / schwebend |

Medientasten (`--locked`) rufen `volume.sh`, `battery.sh brightness-*` und `playerctl` auf. In der
Übersicht heißen sie „Taste Lauter“ usw.; die Namen übersetzt `pretty()` in `keybindings.sh`. Es gibt keinen `bar {}`-Block, keine `mode`-Blöcke und keinen Exit-Befehl per
Kürzel; Abmelden läuft über das Power-Menü. Die letzte Zeile lädt `~/.config/i3-apple/sway-user.conf`.

---

## 8. Rezepte für typische Änderungen

- **Neues Tastenkürzel:** in `config/sway/config` mit einer Zeile `#: …` direkt darüber.
- **Neues Symbol in der Leiste oder einem Popup:**
  1. Den Namen als `*-symbolic` in `eww.yuck` oder im Skript verwenden.
  2. Den Namen samt Ersatznamen in `wanted()` von `bar-icons.py` eintragen.
  3. `test.sh` ausführen; der Abschnitt „Design“ meldet fehlende Symbole.
- **Neues Popup:**
  1. `defwindow` in `eww.yuck` mit Ebene `overlay` und Namespace `eww-popup`; Daten-Polls mit
     `:run-while {popup == "name"}`.
  2. Den Namen in die Fallunterscheidung von `popup.sh` aufnehmen.
  3. Den Knopf in der Leiste `popup.sh <name> ${output}` aufrufen lassen.
- **Neuer Hintergrunddienst:** in `services.sh` mit `running …` oder `pgrep … || start NAME CMD`;
  `start` schließt fd 9 schon. Bei Bedarf in die Abschlussprüfung am Ende aufnehmen.
- **Stil, rofi, dunst, Status-Skripte ändern:** direkt in `config/sway/eww/eww.scss`,
  `config/sway/rofi/`, `config/sway/dunst/dunstrc` bzw. `config/sway/eww/scripts/`. Es gibt keine
  geteilten Dateien mit der i3-Variante mehr.
- **Neue installierte Datei außerhalb von `~/.config/sway`:**
  1. Im Installer anlegen und nichts fremdes überschreiben.
  2. In `backup_paths()` eintragen.
  3. Die README-Tabelle „GNOME und Plasma bleiben unberührt“ ergänzen.
- **Neue Prüfung in `test.sh`:**
  - Helfer: `ok`, `hint`, `bad`, `info`, `need`, `want`, `section`.
  - Was die laufende Sitzung braucht, mit `(( IN_SWAY ))` absichern; was Fenster öffnet, mit
    `(( GUI ))`.
  - GTK-Prüfungen kommen in das eingebettete Python-Heredoc und geben `OK|WARN|FAIL\tText` aus.
  - Niemals Nutzerzustand verändern.

---

## 9. Testen und Fehlersuche

- `bash sway/test.sh` prüft alles und ändert nichts; `--gui` öffnet zusätzlich kurz die beiden
  Fenster. Am aussagekräftigsten ist der Lauf in der laufenden Sitzung „Sway (i3-apple)“.
- Nach Änderungen im Repo: `sway/install.sh --config-only`. Der Installer lädt Sway selbst neu.
- **Logs:** `$RUNTIME/services.log`, `displays.log`, `wallpaper-picker.log`, `record.log`.
- **eww:**
  - Logs: `eww -c ~/.config/sway/eww logs`.
  - Variablen ansehen: `eww -c ~/.config/sway/eww state`.
- **Symbole:** `python3 ~/.config/sway/eww/scripts/bar-icons.py check`.
- In Agenten-Umgebungen gibt es oft keine laufende Sway-Sitzung. Dann kannst du nur Syntax prüfen
  (`bash -n`, `python3 -m py_compile`); sag dem Nutzer, was ungetestet ist.

---

## 10. Bekannte Probleme und offene Punkte

Die Fehler aus der Code-Durchsicht vom Oktober 2026 sind behoben. Offen bleiben:

1. **`dunstrc`** stammt ursprünglich aus der X11-Fassung (`follow = mouse`, `offset = 12x44`).
   Unter Sway sitzen Mitteilungen vielleicht zu tief oder auf dem falschen Bildschirm. Das ist
   nicht geprüft; die Datei gehört jetzt allein Sway und darf angepasst werden.
2. **Die Kürzel-Übersicht** listet Kürzel mit gleicher Beschreibung mehrfach, z. B.
   Super+Leertaste und Super+Strg+Enter. Das ist so gewollt.
3. **Ausstehende Prüfung:** Die Korrekturen wurden ohne laufende Sway-Sitzung geschrieben (nur
   Code-Durchsicht). Nach der nächsten Installation `bash sway/test.sh` in der Sitzung ausführen.
   Das gilt auch für die Erweiterung vom 10.10.2026: Popups im Kontrollzentrum-Stil, Animationen,
   eigene kitty-Fassung, Hintergrund-Auswahl mit Ordnern und robustere SwayFX-Erkennung. Dabei
   wurde nichts ausgeführt, nicht einmal `bash -n` oder `py_compile`.
4. **`build_swayfx` ist ungetestet.** Unbestätigt sind die Repo-URLs (`SWAYFX_URL`,
   `SCENEFX_URL`, `WLROOTS_URL`), das Tag-Muster in `meson.build`, die Namen der meson-Optionen,
   die Liste der Build-Pakete und der 2. Weg mit Unterprojekten (u. a. ob das rpath aus `LDFLAGS`
   die Installation übersteht). Beim ersten Lauf auf Ubuntu 24.04 / KDE neon (wlroots 0.17 →
   SwayFX 0.4, scenefx 0.1) `~/.cache/i3-apple/swayfx-build.log` prüfen.
5. **Umstellung vom 10.10.2026 (eigenständig, SwayFX Pflicht)** ist ebenfalls ungetestet, auch
   ohne `bash -n`.
6. **Änderungen vom 10.10.2026, zweite Runde** (Super+1 ohne Hin- und Herspringen, xembedsniproxy
   nur auf Wunsch, `menu.py`, SwayFX-Animationen samt Nachrüsten, Fingerabdruck) sind ebenfalls
   ohne jede Ausführung geschrieben. Unbestätigt sind besonders:
   - dass SwayFX 0.6 `animation_duration_ms` zur Laufzeit per swaymsg annimmt (`fx_on`/`fx_off`);
   - wie `menu.py` unter WhiteSur aussieht (Zeilenhöhe = `ROW_H`?);
   - ob `fprintd-verify` bei einem Treffer „verify-match“ ausgibt (fprintd ≥ 1.90). `eww.scss` ist die zusammengeführte Fassung aus dem früheren gemeinsamen
   `eww.scss` und `eww-sway.scss` (gleiche Regeln, nur zusammengelegt).
