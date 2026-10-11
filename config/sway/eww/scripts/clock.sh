#!/usr/bin/env bash
# Datum & Uhrzeit: clock.sh bar|long

if locale -a 2>/dev/null | grep -qiE '^de_DE\.utf-?8$'; then
  export LC_TIME=de_DE.UTF-8
  bar='%a. %-d. %b.  %H:%M'
  long='%A, %-d. %B %Y'
else
  bar='%a %b %-d  %H:%M'
  long='%A, %B %-d, %Y'
fi

case $1 in
  long) date "+$long" ;;
  *)    date "+$bar" ;;
esac
