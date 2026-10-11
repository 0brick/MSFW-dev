#!/usr/bin/env bash
# Liefert den Namen der aktiven App und ihren Bildschirm (wie der fette App-Name in macOS).
# Wayland-Apps haben eine app_id (z. B. org.mozilla.firefox → „Firefox“),
# X-Apps (XWayland) eine Fensterklasse.

emit() {
  swaymsg -t get_tree -r 2>/dev/null | jq -c '
    first(
      .nodes[] | select(.type == "output") as $o
      | .. | objects | select(.focused? == true)
      | {
          output: $o.name,
          title: (if .shell? != null then (.name // "") else "" end),
          # leere app_id zählt als fehlend (jqs „//“ greift nur bei null)
          app: (if .shell? != null
                then (([.app_id, .window_properties.class?] | map(select(type == "string" and . != "")) | .[0]) // "")
                else "" end
                | split(".") | (last // "")
                | if . == "" then . else (.[0:1] | ascii_upcase) + .[1:] end)
        }
    ) // {output: "", app: "", title: ""}'
}

while true; do
  emit
  swaymsg -t subscribe -m -r '["window","workspace"]' 2>/dev/null | while read -r _; do emit; done
  sleep 1
done
