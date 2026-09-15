#!/bin/sh

# Calendar / clock
# Left click -> open Calendar.app
# Otherwise refresh English date label
# On calendar-day change -> rebuild today's focus bar

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
DATE_FILE="$CACHE_DIR/last_calendar_day"

case "$SENDER" in
  mouse.clicked)
    open -a Calendar
    ;;
esac

TODAY="$(date '+%Y-%m-%d')"
PREV=""
if [ -f "$DATE_FILE" ]; then
  read -r PREV < "$DATE_FILE"
fi

# Only rebuild when we already knew a previous day and it flipped
# (startup still uses sketchybarrc's one-shot focus.sh).
if [ -n "$PREV" ] && [ "$TODAY" != "$PREV" ]; then
  NAME=focus SENDER=date_changed "$PLUGIN_DIR/focus.sh"
fi
mkdir -p "$CACHE_DIR"
printf '%s\n' "$TODAY" > "$DATE_FILE"

sketchybar --set "$NAME" label="$(LC_TIME=C date '+%a %m/%d %H:%M')"
