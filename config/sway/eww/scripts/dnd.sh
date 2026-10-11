#!/usr/bin/env bash
# „Nicht stören“ über dunst: dnd.sh status|toggle|clear
source "$(dirname "$0")/lib.sh"

case $1 in
  status) dunstctl is-paused 2>/dev/null || echo false ;;
  toggle)
    dunstctl set-paused toggle
    eww_ update dnd="$(dunstctl is-paused)"
    ;;
  clear)
    dunstctl close-all
    dunstctl history-clear
    ;;
esac
