# i3-apple · Sway (Wayland)

Eine Arbeitsumgebung im macOS-Stil für **Sway/SwayFX (Wayland)** – eigenständig, alles Nötige liegt in diesem Ordner: Menüleiste mit Popups, Spotlight, Mitteilungen, Einstellungen, Glas-Unschärfe, Schatten und runde Ecken. Besonderheiten:

1. **Tastenkürzel-Übersicht (Super + Strg + K):** Alle Beschreibungen stehen exakt untereinander, egal wie lang die Tastenkombination ist.
2. **Hintergrundbild (Super + Strg + W):** eigenes Auswahlfenster mit Seitenleiste, **Ordnern zum Anklicken** und Vorschau-Raster, dazu Pfadsuche mit Autovervollständigung.
3. **Bildschirme (Super + P → „Anordnung & Skalierung bearbeiten …“):** Bildschirme mit der Maus anordnen, **Skalierung**, Auflösung, Bildrate und Drehung einstellen.

## Installation

```bash
cd ~/Projects/i3-apple
sway/install.sh
```

Danach abmelden und am Anmeldebildschirm (SDDM, unten links) die Sitzung **Sway (i3-apple)** wählen. Plasma und andere Sitzungen bleiben daneben unverändert.

**SwayFX ist Pflicht.** Fehlt es, baut der Installer es bei jedem Lauf (auch mit `--config-only`). Gelingt das nicht, bricht er ab, bevor er die Konfiguration übernimmt – die Ursache steht in `~/.cache/i3-apple/swayfx-build.log`.

| Option | Wirkung |
|---|---|
| `--config-only` | nur Konfiguration neu kopieren (nach eigenen Änderungen im Repo) |
| `--no-packages` | keine apt-Pakete installieren, auch keine Build-Pakete für SwayFX (Zed, Firefox und Thunderbird werden ebenfalls übersprungen) |
| `--no-themes` | WhiteSur und macOS-Cursor überspringen |
| `--no-eww` | eww nicht bauen |
| `--no-rofi` | rofi nicht mit Wayland bauen (es läuft dann über XWayland) |
| `--backup-only` | nur sichern, nichts verändern |
| `--no-backup` | ohne Sicherung installieren |
| `--backup-dir=PFAD` | Sicherungen in einem anderen Ordner ablegen |
| `--restore [ARCHIV]` | Sicherung zurückspielen (ohne Angabe: die neueste) |

## Selbsttest

```bash
bash sway/test.sh          # prüft alles, ändert nichts, öffnet keine Fenster
bash sway/test.sh --gui    # öffnet zusätzlich kurz beide Fenster und sendet eine Testmitteilung
```

Am aussagekräftigsten im Terminal der laufenden Sitzung „Sway (i3-apple)“. Geprüft werden:
- **Programme:** alle Programme und Abhängigkeiten, auch ob eww und rofi Wayland können, sowie die OCR-Sprachen.
- **Konfiguration:** die Konfigurationsdateien, Sways eigene Prüfung (`sway -C`), ob alle Skripte ausführbar sind und ihre Syntax.
- **Design:** Schriften, Themes, Mauszeiger und Symbole, auch ob die Menüleiste jedes ihrer Symbole findet.
- **Fenster und Anordnung:** Python/GTK samt Cairo-Anbindung und Bildformaten, ob sich das Hintergrund-Fenster aufbauen lässt, die Einrast-Logik der Bildschirme und ob die Tastenkürzel-Spalten untereinander stehen.
- **Laufende Dienste:** Menüleiste je Bildschirm, swaybg, swayidle, kanshi, dunst, Zwischenablage.
- **Getrennt von GNOME/Plasma:** ob diese Desktops unberührt geblieben sind.

Ergebnis: ✓ in Ordnung, ! Hinweis, ✗ Fehler. Der Exit-Code ist die Anzahl der Fehler.

## Eigene Einstellungen bleiben erhalten

Ein erneuter Lauf von `sway/install.sh`, auch mit `--config-only`, setzt nichts zurück, was du eingestellt hast.

| Was | Wie es erhalten bleibt |
|---|---|
| **Bildschirm-Anordnung, Skalierung, Auflösung** | Sway setzt Bildschirme beim Neuladen zurück. Deshalb sichern Super + Shift + R und der Installer den Zustand vorher (`reload.sh`), und `services.sh` stellt ihn danach wieder her. Jede Änderung über Super + P (Schnellwahl, Profil, Fenster) wird außerdem als Profil dieser Bildschirm-Kombination gemerkt und übersteht so auch Neuanmeldung und Neustart. |
| **Dateien in `~/.config/sway`** und `env-sway.sh` | Der Installer merkt sich die Prüfsumme jeder installierten Datei:<br>• Unverändert → wird aktualisiert.<br>• Nur von dir geändert → **bleibt**.<br>• Von dir *und* im Repo geändert → deine Fassung wird nach `~/.config/i3-apple/lokale-aenderungen/<Datum>/` gesichert, und der Installer meldet das.<br>Eigene zusätzliche Dateien bleiben immer liegen. |
| **Eigene Sway-Befehle** | Gehören am besten in `~/.config/i3-apple/sway-user.conf`. Die Datei wird zuletzt geladen, hat also Vorrang, und der Installer legt sie nur an, nie überschreibt er sie. Auch `input.sh` lässt dort eingestellte `input`-Befehle in Ruhe. |
| Hintergrundbild, gemerkte Ordner, Hell/Dunkel, Favoriten, Touchpad & Tastatur, Akku-Prozentanzeige, Autostart-Liste | liegen in `~/.config/i3-apple` und werden nie angefasst. |
| Profile (`display-profiles.json`, `~/.config/kanshi/config`) | Der Installer legt die kanshi-Datei nur an, wenn sie fehlt. Neu geschrieben wird sie nur vom Bildschirm-Fenster. |
| GTK-Einstellungen der Sitzung | Die eigene dconf-Datenbank wird nur angelegt, wenn sie fehlt. Theme und Symbole folgen Hell/Dunkel. Schrift, Cursor und Fensterknöpfe setzt `theme.sh` nur, solange du sie nicht selbst geändert hast, und das einmal pro Anmeldung statt bei jedem Neuladen. |
| Effekte aus (Super + Shift + A, Spielmodus) | bleiben auch nach dem Neuladen aus. |
| Eigene kitty-Einstellungen | gehören in `~/.config/sway/kitty/eigene.conf`. Sie wird zuletzt geladen; der Installer legt sie nie an und überschreibt sie nie. |

## GNOME und Plasma bleiben unberührt

Der Sway-Installer verändert nichts, was GNOME, KDE Plasma oder andere Desktops benutzen. Fällt Sway aus, meldest du dich einfach in Plasma oder GNOME an, und alles ist wie vorher.

| Bereich | So bleibt es getrennt |
|---|---|
| GTK-Theme, Symbole, Schrift, Hell/Dunkel | Die Sway-Sitzung nutzt eine **eigene dconf-Datenbank** (`~/.config/dconf/i3apple-sway`, über `DCONF_PROFILE`). Die gsettings von GNOME und Plasma werden nie geschrieben. |
| `~/.config/gtk-3.0`, `gtk-4.0`, `kdeglobals`, Standard-Cursor | werden nicht angefasst. WhiteSur wird ohne die Option `-l` installiert, die GTK4-Apps überall umfärben würde. Themes und Cursor liegen nur zur Auswahl bereit. |
| Symbol-Theme der Menüleiste | `~/.local/share/icons/i3apple-sway-bar` und `…-fallback` sind versteckt (`Hidden=true`), erscheinen in keiner Theme-Auswahl und werden nur von der Sway-Menüleiste benutzt. |
| rofi, dunst, kitty | Eigene Konfigurationen in `~/.config/sway/…`. `~/.config/rofi`, `dunst` und `kitty` bleiben unverändert. |
| Mitteilungen | Ein D-Bus-Eintrag in `~/.local/share/dbus-1/services/` sorgt dafür, dass dunst nur in der Sway-Sitzung startet. In Plasma und GNOME kann es die Mitteilungen nicht mehr übernehmen. |
| Autostart | Ausschalten schreibt die App nur in `~/.config/i3-apple/autostart-disabled-sway`. Hinzugefügte Apps bekommen eigene Dateien `i3apple-sway-*.desktop` mit `OnlyShowIn=sway`. Bestehende Einträge in `~/.config/autostart` werden nie verändert. |
| Umgebungsvariablen | Sie gelten nur in der Sitzung „Sway (i3-apple)“. An systemd/D-Bus gehen sie nur, wenn keine andere grafische Sitzung läuft, und beim Abmelden werden sie wieder entfernt. |
| Hintergrunddienste | kanshi, swayidle, gammastep, cliphist und xsettingsd startet nur die Sway-Sitzung. Pakete mit eigenem Tray-Applet im Autostart (z. B. blueman) werden nicht installiert. |
| Pakete | werden nie entfernt: Jedes Paket wird vorher simuliert, die Installation läuft mit `apt-get --no-remove` und **ohne empfohlene Zusatzpakete**. SwayFX ersetzt Sway nur, wenn Sway noch nicht installiert ist. |
| rofi-Build | landet in `~/.local/share/i3-apple/rofi-wayland` und wird nur von der Sway-Sitzung benutzt. |
| SwayFX-Build | landet in `~/.local/share/i3-apple/swayfx-<Version>` (Verweis `swayfx`). Nur `env-sway.sh` stellt ihn vorn in den PATH. Das installierte Sway-Paket und die normale „Sway“-Sitzung bleiben unverändert. Zum Bauen kommen nur `-dev`-Pakete dazu (nach denselben Regeln: simuliert, nichts entfernt). |

**Einzige Ausnahme:** Ein vorhandenes `~/.local/bin/eww` ohne Wayland wird durch eine Version für X11 *und* Wayland ersetzt; unter X11 läuft es weiter wie bisher.

**Systemdateien:** Für die Anmeldesitzung legt der Installer mit `sudo` zwei neue Dateien an. Vorhandene Sitzungen ändern sich nicht.
- `/usr/share/wayland-sessions/sway-apple.desktop`
- `/usr/local/bin/sway-apple-session` lädt `~/.config/i3-apple/env-sway.sh`, startet Sway und räumt beim Abmelden auf.

**Sicherung:** Vor jeder Änderung entsteht `~/i3-apple-Backups/sway-apple-backup-<Datum>.tar.gz` mit allem, was der Installer im Benutzerordner anlegt: `~/.config/sway`, `kanshi`, `i3-apple`, `autostart`, die eigene dconf-Datenbank, das Symbol-Theme der Menüleiste und den D-Bus-Eintrag. Eine schon vorhandene eigene Sway-Konfiguration wird zusätzlich als `~/.config/sway.bak-<Datum>` beiseitegelegt.

## Bausteine

Alles, was installiert wird, stammt aus diesem Ordner (`sway/`) – Konfiguration, Menüleisten-Skripte, Stil, rofi, dunst und kitty.

| Bereich | Umsetzung |
|---|---|
| Ecken, Schatten, Glas-Unschärfe | **SwayFX** (`config/sway/fx-effects.conf`) |
| Animationen (Fenster, Arbeitsflächen) | **SwayFX ab 0.6** (`config/sway/fx-animations.conf`) |
| Menüleiste & Popups | eww mit Layer-Shell (`config/sway/eww/`). Der Installer baut eww für X11 *und* Wayland. |
| Launcher & Menüs | rofi mit Wayland. Kann das rofi der Distribution kein Wayland, baut der Installer rofi 2 nach `~/.local/share/i3-apple/rofi-wayland`. Diesen Ordner nimmt nur die Sway-Sitzung in den PATH. |
| Hintergrundbild | swaybg |
| Sperrbildschirm | swaylock + swayidle (weichgezeichnetes Bild je Bildschirm), Fingerabdruck über fprintd |
| Bildschirmprofile | kanshi |
| Bildschirmfotos & -aufnahmen | **Super + Druck** öffnet eine Auswahl wie ⌘⇧5 am Mac:<br>• **Fotos** (grim + slurp): Bereich, Fenster, Bildschirm, alle Bildschirme, Selbstauslöser, Bearbeiten (swappy)<br>• **Videos** (wf-recorder): Bildschirm oder Bereich, ohne Ton, mit Systemton oder mit Mikrofon<br>Während einer Aufnahme zeigt die Menüleiste einen roten Punkt mit der Laufzeit, ein Klick darauf beendet sie. **Super + Alt + R** startet bzw. beendet eine Aufnahme direkt. Die Videos landen in `~/Videos/Bildschirmaufnahmen`, die Datei kommt in die Zwischenablage. |
| Zwischenablage-Verlauf | cliphist (sonst clipman) |
| Blaulichtfilter | gammastep |
| Fensterübersicht (Super + Tab) | eigene Liste über Sways IPC, mit App-Symbolen |
| Tastaturlayout | aus `~/.config/i3-apple/input`, sonst aus den KDE-Einstellungen, sonst aus `/etc/default/keyboard` |
| Super + Shift + A | Effekte (Unschärfe, Schatten) an/aus |
| Super + Shift + R | Sway neu laden |

## Menüs und Übersichten

Tastenkürzel (Super + Strg + K), Fensterübersicht (Super + Tab), Einstellungen, Autostart-Apps, Ausschalten, Bildschirme, Bildschirmfoto und Erscheinungsbild öffnen sich in einem eigenen Fenster (`scripts/menu.py`):

- **Echte Spalten:** In der Kürzel-Übersicht beginnen alle Beschreibungen an derselben Stelle, in der Fensterübersicht stehen App, Titel und Arbeitsfläche untereinander. Die Breite richtet sich nach dem längsten Eintrag, die Schrift spielt keine Rolle mehr.
- **Animation:** Das Fenster blendet ein und die Liste gleitet leicht nach oben. Ab SwayFX 0.6 kommt die Öffnen-Animation von SwayFX dazu.
- **Bedienung:** Tippen filtert, ↑/↓ oder Tab wählen, Enter oder ein Klick übernimmt, Esc oder ein Klick daneben schließt.
- Spotlight (Super + Leertaste) bleibt rofi. Fehlt GTK für Python, öffnen sich auch die Menüs mit rofi.

## Animationen

SwayFX animiert ab Version 0.6 das Öffnen und Schließen von Fenstern, das Verschieben und Vergrößern sowie den Wechsel der Arbeitsfläche (`config/sway/fx-animations.conf`, 250 ms). Ist ein älteres SwayFX installiert, baut der Installer einmalig eine neuere Version. Klappt das nicht, bleibt die bisherige, und der Installer versucht es erst nach einer Woche wieder. **Super + Shift + A** und der Spielmodus schalten die Animationen zusammen mit den übrigen Effekten ab.

## Sperrbildschirm mit Fingerabdruck

Sind mit fprintd Fingerabdrücke eingerichtet (dieselben, mit denen GDM entsperrt), entsperrt auch der Finger. Auf dem Sperrbild steht dann „Finger auflegen oder Passwort eingeben“, und das Passwort funktioniert weiter. Nötig ist swaylock ab 1.6. Das Protokoll liegt in `$XDG_RUNTIME_DIR/sway-apple/fingerprint.log`.

## Alte Tray-Symbole (XEmbed)

Sehr alte Programme (Wine, ältere Java-Apps) nutzen noch XEmbed statt StatusNotifier. Deren Symbole zeigt die Menüleiste nur, wenn `~/.config/i3-apple/xembed-tray` existiert (`touch ~/.config/i3-apple/xembed-tray`, dann Super + Shift + R). Der dazu nötige xembedsniproxy legt in Sway ein schwarzes Quadrat oben links über die Leiste, darum ist er normalerweise aus.

## Hintergrundbild (Super + Strg + W)

Ein Fenster wie in den macOS-Systemeinstellungen: links eine Seitenleiste, rechts ein Raster mit Vorschaubildern.

- **Seitenleiste:** „Alle Bilder“ zeigt alles aus den Hintergrund-Ordnern. Darunter stehen die Hintergrund-Ordner einzeln, dazu „Bilder“ und der persönliche Ordner. **Ordner hinzufügen …** wählt einen weiteren Ordner aus und merkt ihn sich dauerhaft.
- **Ordner öffnen:** Ordner erscheinen im Raster als Kacheln mit dem ersten Bild als Vorschau und der Anzahl der Bilder. Ein Klick öffnet sie, das Raster gleitet zum neuen Inhalt. **‹** oder **Alt + ←** geht zurück, **Alt + ↑** öffnet den übergeordneten Ordner. Bei leerem Suchfeld geht auch **Rücktaste** zurück.
- **Übernehmen:** Ein Klick auf ein Bild (oder Enter) setzt es und schließt das Fenster. Das aktuelle Bild hat einen blauen Rahmen.
- **Suchen:** Tippen filtert den gerade offenen Ordner bzw. „Alle Bilder“ nach Namen, auch nach Wortteilen und unscharf („hgr“ findet „Hintergrund“).
- **Pfad eingeben:** Beginnt die Eingabe mit `/`, `~` oder `.`, zeigt das Raster sofort die Unterordner und Bilder dieses Ordners.
  - Vorschläge klappen unter dem Suchfeld auf und werden direkt im Feld ergänzt.
  - **Tab** vervollständigt wie im Terminal, bei mehreren Treffern bis zum gemeinsamen Anfang. Enter öffnet den Ordner.
  - Versteckte Ordner erscheinen, sobald der Name mit `.` beginnt.
- **Tastatur:** **↓** springt ins Raster. **Esc** leert zuerst das Suchfeld und schließt beim zweiten Druck das Fenster.
- **Gemerkte Ordner:** Ein Ordner, aus dem du ein Bild wählst oder den du hinzufügst, landet in `~/.config/i3-apple/wallpaper-dirs`. Er erscheint danach in der Seitenleiste, seine Bilder in „Alle Bilder“ und bei „zufälliges Hintergrundbild“ (Super + Shift + W).
- Vorschaubilder werden in `~/.cache/i3-apple/thumbs` zwischengespeichert.
- Ohne python3-gi zeigt Super + Strg + W das bisherige rofi-Raster. Dort übernimmt Strg + Enter einen eingetippten Pfad.

## Bildschirme anordnen & skalieren

**Super + P** öffnet die Schnellwahl wie bisher: extern rechts, links oder oben erweitern, spiegeln, nur intern, nur extern und Profile. Mit „Anordnung & Skalierung bearbeiten …“ oder über Einstellungen → „Bildschirme anordnen & skalieren“ öffnet sich das Fenster **Bildschirme**:

- **Anordnen:** Die Bildschirme erscheinen mit dem aktuellen Hintergrundbild in ihrer echten Größe. Du ziehst sie mit der Maus an die gewünschte Stelle. Beim Loslassen rasten sie lückenlos am nächsten Rand ein, nahe der Kante auch bündig oben, unten oder mittig. Überlappen ist nicht möglich.
- **Skalierung:** Stufen 100 bis 300 % oder frei in 5-%-Schritten (50 bis 400 %). Daneben steht, wie groß der Bildschirm damit wirkt, zum Beispiel „wirkt wie 1707 × 1067“. Ändert sich die Größe, rücken die Nachbarbildschirme automatisch nach.
- **Außerdem:** Auflösung (die native ist markiert), Bildwiederholrate, Drehung sowie Ein- und Ausschalten. Mindestens ein Bildschirm bleibt immer an.
- **Anwenden mit Sicherheitsnetz:** Nach „Anwenden“ fragt ein Dialog „Beibehalten?“. Ohne Antwort stellt er nach 15 Sekunden die vorherigen Einstellungen wieder her.
- **Automatisch gemerkt:** Beim Beibehalten wird die Anordnung als Profil für genau diese Bildschirm-Kombination gespeichert. kanshi lädt es beim nächsten Anstecken von selbst. Mit „Als Profil speichern …“ gibst du ihm einen Namen.
  - Je Kombination gibt es ein Profil. Bildschirme werden über Hersteller, Modell und Seriennummer erkannt, also unabhängig vom Anschluss.
  - Die Profile liegen in `~/.config/i3-apple/display-profiles.json`. Daraus erzeugt das Fenster `~/.config/kanshi/config`. Eine eigene kanshi-Konfiguration wird beim ersten Speichern gesichert (`config.bak-<Datum>`).
- **Spiegeln:** Sway kann von sich aus nicht spiegeln. Die Schnellwahl zeigt den internen Bildschirm deshalb mit `wl-mirror` im Vollbild auf den externen. Das Spiegeln wird im Profil gemerkt: Steckst du dieselben Bildschirme wieder an, wird wieder gespiegelt. Wechselst du zu einem anderen Profil, endet das Spiegeln.
- **Profilnamen:** Gehört ein Name schon zu einer anderen Bildschirm-Kombination, bleibt deren Profil erhalten. Das neue bekommt einen Zusatz, z. B. „Büro (2)“.

Menüleiste und Hintergrund passen sich nach jeder Änderung von selbst an.

## Anpassen

| Was | Wo |
|---|---|
| Eigene Sway-Befehle (bleiben bei jeder Installation) | `~/.config/i3-apple/sway-user.conf` |
| Effekte: Eckenradius, Schatten, Unschärfe | `config/sway/fx-effects.conf` |
| Aussehen der Menüleiste und Popups, Animationen | `config/sway/eww/eww.scss` |
| Spotlight (rofi), Mitteilungen (dunst) | `config/sway/rofi/`, `config/sway/dunst/dunstrc` |
| Terminal (kitty), Farben für Hell/Dunkel | `config/sway/kitty/` – eigene Wünsche in `~/.config/sway/kitty/eigene.conf` |
| Fensterregeln, Kürzel | `config/sway/config` |
| Umgebungsvariablen der Sitzung | `home/env-sway.sh` (→ `~/.config/i3-apple/env-sway.sh`) |
| Favoriten, Touchpad & Tastatur (Vorlagen) | `home/favorites`, `home/input` (→ `~/.config/i3-apple/…`, nur wenn noch nicht vorhanden) |

Nach Änderungen im Repo: `sway/install.sh --config-only`

## Hinweise

- **SwayFX** bringt runde Fensterecken (12 px, auch allein auf einer Arbeitsfläche), Schatten und Unschärfe.
  - **Als Paket:** Bietet die Distribution SwayFX an und ist Sway noch nicht installiert, kommt SwayFX statt Sway.
  - **Selbst gebaut:** Sonst baut der Installer SwayFX aus dem Quellcode, z. B. auf Ubuntu 24.04 und KDE neon. Zuerst versucht er die neueste SwayFX- und scenefx-Version, die zur wlroots-Version des Systems passt. Gibt es keine passende (z. B. Debian 12/13), baut er eine aktuelle SwayFX-Version mit eigenem wlroots und scenefx als meson-Unterprojekten. Das dauert einige Minuten; das Protokoll liegt in `~/.cache/i3-apple/swayfx-build.log`.
  - **Wenn es nicht klappt:** bricht der Installer ab und zeigt die letzten Zeilen des Protokolls. Meist fehlt ein `-dev`-Paket oder die Internetverbindung.
  - **Nach einem System-Update:** Startet das gebaute SwayFX nicht mehr, nimmt die Sitzung vorübergehend das normale Sway, und der nächste Lauf von `sway/install.sh` (auch `--config-only`) baut neu.
  - **Neu bauen erzwingen:** `rm -rf ~/.local/share/i3-apple/swayfx*` und dann `sway/install.sh --config-only`.
  - **Ob die Effekte aktiv sind,** entscheidet der Sitzungsstart: Nur wenn wirklich SwayFX läuft, bekommt `~/.config/sway/fx.conf` die Effekt-Befehle. Erkannt wird SwayFX an `sway --version` oder daran, dass das Programm `corner_radius` kennt.
- **Animationen:** Sway und SwayFX können Fenster und Arbeitsflächen nicht animieren. Bewegung gibt es deshalb dort, wo die Programme selbst zeichnen:
  - Menüleiste und Popups blenden weich ein. Schalter gleiten, Hover-Flächen gehen fließend über, die aktive Arbeitsfläche wächst zur Pille, der Aufnahme-Punkt pulsiert.
  - In der Hintergrund-Auswahl gleitet das Raster beim Ordnerwechsel, Vorschaubilder blenden ein.
  - kitty zeigt ab Version 0.37 eine Zeigerspur; ab 0.36 blendet der Zeiger beim Blinken weich.
- **kitty** folgt Hell/Dunkel (Super + Shift + M). Offene Fenster wechseln die Farben ab kitty 0.28 sofort, ältere Versionen beim nächsten Öffnen.
- **Dienste der Sitzung** (dunst, swayidle, Zwischenablage, kanshi, xsettingsd, Bildschirm-Überwachung) startet `services.sh` beim Anmelden und bei jedem Neuladen (Super + Shift + R), und zwar nur, was fehlt. Ist ein Dienst abgestürzt, reicht also ein Neuladen. Protokoll: `$XDG_RUNTIME_DIR/sway-apple/services.log`.
- **Symbole der Menüleiste** kommen aus einem eigenen Symbol-Theme (`i3apple-sway-bar`), nicht aus den GTK-Einstellungen der Sitzung. Es nimmt WhiteSur. Fehlt dort ein Symbol, springen Adwaita oder Breeze ein, und Namen, die es nur bei GNOME gibt (z. B. `battery-level-50-symbolic`), werden auf das passende Breeze-Symbol umgeleitet. Abgleich beim Installieren und einmal pro Anmeldung, von Hand mit `python3 ~/.config/sway/eww/scripts/bar-icons.py`. Zeigt die Leiste trotzdem Platzhalter, nennt `sway/test.sh` die fehlenden Symbole.
- **XWayland** ist an. X11-Programme laufen weiter, ihre GTK-Einstellungen bekommen sie über einen eigenen xsettingsd.
- **Eigene GTK-Einstellungen:** Wegen der eigenen dconf-Datenbank startet die Sway-Sitzung beim ersten Mal mit den GTK-Standardwerten, dann setzt `theme.sh` Theme, Symbole, Cursor und Schrift. Was du in Sway z. B. über die GNOME-Einstellungen änderst, bleibt in Sway.
- **KDE-Apps** folgen in Sway den Plasma-Einstellungen, lesen sie aber nur.
- **Bildschirmfreigabe** (Browser, Videokonferenzen) läuft über `xdg-desktop-portal-wlr`. Der Sitzungsstart gibt die Wayland-Umgebung dafür an D-Bus und systemd weiter.
- **WLAN-Passwörter aus KWallet:** Plasma legt sie dort ab, ohne Plasma kommt NetworkManager nicht heran. Beim ersten Verbinden fragt das WLAN-Popup deshalb einmal nach dem Passwort und speichert es systemweit.
- **Startest du die normale Sitzung „Sway“** statt „Sway (i3-apple)“, lädt die Konfiguration zwar, aber ohne die Umgebungsvariablen. Dann fehlen Cursor, Qt-Theme und Wayland-Einstellungen für Firefox, Qt und Electron, und ein selbst gebautes rofi wird nicht gefunden.
