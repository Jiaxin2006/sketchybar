#!/bin/sh

# Auto-close a popup after DELAY seconds unless a newer schedule token exists.
# Usage: popup_autoclose.sh <item_name> [delay_seconds]

ITEM="${1:-}"
DELAY="${2:-3}"
[ -z "$ITEM" ] && exit 0

CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
mkdir -p "$CACHE_DIR"
TOKEN_FILE="$CACHE_DIR/popup_${ITEM}.token"
TOKEN="$(date +%s%N)"
echo "$TOKEN" > "$TOKEN_FILE"

(
  sleep "$DELAY"
  CURRENT="$(cat "$TOKEN_FILE" 2>/dev/null)"
  if [ "$CURRENT" = "$TOKEN" ]; then
    sketchybar --set "$ITEM" popup.drawing=off
  fi
) >/dev/null 2>&1 &
