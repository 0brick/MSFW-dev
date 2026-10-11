#!/usr/bin/env bash
# Text aus einem Bildschirmbereich erkennen und kopieren (⌘⌥A)
if ! command -v tesseract >/dev/null; then
  notify-send -a "Texterkennung" "Texterkennung nicht verfügbar" "Dafür wird tesseract gebraucht (Paket tesseract-ocr)."
  exit 1
fi
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/sway-apple"
mkdir -p "$RUNTIME"
img="$RUNTIME/ocr.png"
g=$(slurp -d -b 00000066 -c 0a84ffff -w 2) || exit 0
grim -g "$g" "$img" || exit 0
text=$(tesseract "$img" - -l deu+eng 2>/dev/null || tesseract "$img" - 2>/dev/null)
rm -f "$img"
if [[ -n ${text//[[:space:]]/} ]]; then
  printf '%s' "$text" | wl-copy
  # Vorschau nach Zeichen kürzen (head -c könnte ein UTF-8-Zeichen zerteilen)
  preview=${text:0:120}
  (( ${#text} > 120 )) && preview+=" …"
  notify-send -a "Texterkennung" "Text kopiert" "$preview"
else
  notify-send -a "Texterkennung" "Kein Text erkannt"
fi
