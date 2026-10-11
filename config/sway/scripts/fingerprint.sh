#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  Entsperren per Fingerabdruck, solange swaylock läuft (startet lock.sh).
#  Nutzt fprintd mit den schon eingerichteten Fingerabdrücken – dieselben,
#  mit denen auch der GDM-Anmeldebildschirm entsperrt. Erkennt fprintd den
#  Finger, bekommt swaylock SIGUSR1: Damit entsperrt es und beendet sich
#  (man swaylock, „SIGNALS“). Das Passwort funktioniert parallel weiter.
#
#  fingerprint.sh available  → Exit 0, wenn es nutzbar ist (Leser, Finger, swaylock ≥ 1.6)
#  fingerprint.sh            → Schleife bis zum Entsperren (lock.sh startet sie abgelöst)
#  Protokoll: $XDG_RUNTIME_DIR/sway-apple/fingerprint.log
# ═══════════════════════════════════════════════════════════════════
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
LOG="$RUNTIME/fingerprint.log"

# Erst ab swaylock 1.6 heißt SIGUSR1 „entsperren“ – ältere würden daran
# beendet, und der Bildschirm bliebe ohne Sperrprogramm gesperrt (rot).
swaylock_ok() {
  local v
  v=$(swaylock --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
  [[ -n $v && $(printf '%s\n%s\n' 1.6 "$v" | sort -V | head -n1) == 1.6 ]]
}

available() {
  command -v fprintd-verify >/dev/null && command -v fprintd-list >/dev/null || return 1
  swaylock_ok || return 1
  # Mindestens ein eingerichteter Finger („ - #0: right-index-finger“)
  timeout 5 fprintd-list "$USER" 2>/dev/null | grep -qE '^[[:space:]]*-[[:space:]]*#[0-9]+'
}

if [[ ${1:-} == available ]]; then
  available
  exit
fi

# Nur eine Schleife gleichzeitig (Sperren per Kürzel und swayidle können sich treffen)
exec 7>"$RUNTIME/fingerprint.lock"
flock -n 7 || exit 0
if [[ -f $LOG ]] && (( $(wc -l < "$LOG") > 300 )); then
  tail -n 100 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
fi
exec >>"$LOG" 2>&1
log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
available || { log "Fingerabdruck nicht verfügbar (fprintd, Finger oder swaylock ≥ 1.6 fehlt)"; exit 0; }

locked() { pgrep -u "$UID" -x swaylock >/dev/null; }

# Kurz warten, bis swaylock läuft (lock.sh startet uns direkt davor)
for _ in 1 2 3 4 5 6 7 8 9 10; do locked && break; sleep 0.3; done
locked || exit 0
log "warte auf Finger"

out="$RUNTIME/fingerprint.out"
fails=0
while locked; do
  # Jeder Durchgang ist ein Versuch; fprintd gibt den Leser frei, sobald
  # fprintd-verify endet oder beendet wird
  fprintd-verify "$USER" >"$out" 2>&1 7>&- &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ! locked; then            # mit Passwort entsperrt → Leser freigeben
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      log "mit Passwort entsperrt"
      exit 0
    fi
    sleep 0.3
  done
  wait "$pid" 2>/dev/null
  # „verify-match“ ist kein Teil von „verify-no-match“ – der Vergleich ist eindeutig
  if grep -q 'verify-match' "$out"; then
    log "Finger erkannt – entsperre"
    pkill -USR1 -u "$UID" -x swaylock
    exit 0
  elif grep -q 'verify-no-match' "$out"; then
    fails=0
    sleep 0.5                    # falscher Finger: gleich noch einmal
  else
    # Leser belegt, nach dem Aufwachen noch nicht bereit, Zeitüberschreitung …
    fails=$((fails + 1))
    (( fails == 1 || fails % 10 == 0 )) && log "fprintd-verify: $(tail -n 1 "$out")"
    if (( fails < 5 )); then sleep 2; else sleep 10; fi
  fi
done
rm -f "$out"
