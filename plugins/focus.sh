#!/bin/sh

# Today's focus: total time label + continuous track segments per session.
# Scale: ~3 minutes = 1px. Min 3px / max 36px per segment.
# Colors lerp ink gradient by session order (0x551e1e1e → 0xcc1e1e1e).
# When today's total focus reaches 8 hours, move CPU/RAM to the right.

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
case "$SENDER" in
  mouse.clicked|mouse.exited.global|space_change|display_change|front_app_switched|routine)
    exec python3 "$PLUGIN_DIR/timer.py" stats ;;
esac
LOG_DIR="${SKETCHYBAR_DATA_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}/data}"
TODAY="$(date '+%Y-%m-%d')"
DAY_FILE="$LOG_DIR/focus_${TODAY}.log"
MIN_W=3
MAX_W=36
MOVE_SECS="${FOCUS_MOVE_SECS:-28800}"  # 8 hours
COLOR_START="0x551e1e1e"
COLOR_END="0xcc1e1e1e"

SESSION_DURS=$(python3 "$PLUGIN_DIR/timer.py" durations) || exit 1

# Remove only existing focus.s* items (do not sweep missing ids — that spams the log)
sketchybar --query bar 2>/dev/null | python3 -c '
import sys, json, subprocess
try:
    items = json.load(sys.stdin).get("items", [])
except Exception:
    items = []
for name in items:
    if name.startswith("focus.s"):
        subprocess.run(["sketchybar", "--remove", name],
                       stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
'

# Pass 1: collect valid session durations
DURS=""
TOTAL=0
N=0
while IFS= read -r LINE || [ -n "$LINE" ]; do
  DUR=$(echo "$LINE" | awk '{print $NF}')
  case "$DUR" in
    ''|*[!0-9]*) continue ;;
  esac
  [ "$DUR" -le 0 ] && continue
  TOTAL=$((TOTAL + DUR))
  N=$((N + 1))
  if [ -z "$DURS" ]; then
    DURS="$DUR"
  else
    DURS="$DURS $DUR"
  fi
done <<EOF
$SESSION_DURS
EOF

# Precompute gradient colors for N segments
if [ "$N" -gt 0 ]; then
  COLORS=$(COLOR_START="$COLOR_START" COLOR_END="$COLOR_END" N="$N" python3 -c '
import os
start = int(os.environ["COLOR_START"], 16)
end = int(os.environ["COLOR_END"], 16)
n = int(os.environ["N"])

def channels(c):
    return ((c >> 24) & 0xFF, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)

sa, sr, sg, sb = channels(start)
ea, er, eg, eb = channels(end)
out = []
for i in range(n):
    t = 0.5 if n == 1 else i / (n - 1)
    a = round(sa + (ea - sa) * t)
    r = round(sr + (er - sr) * t)
    g = round(sg + (eg - sg) * t)
    b = round(sb + (eb - sb) * t)
    out.append(f"0x{a:02x}{r:02x}{g:02x}{b:02x}")
print(" ".join(out))
')
fi

# Pass 2: draw continuous track segments
IDX=0
PREV="focus"
for DUR in $DURS; do
  MINS=$(( (DUR + 59) / 60 ))
  [ "$MINS" -lt 1 ] && MINS=1
  # 3 minutes → 1px
  W=$(( (MINS + 2) / 3 ))
  [ "$W" -lt "$MIN_W" ] && W=$MIN_W
  [ "$W" -gt "$MAX_W" ] && W=$MAX_W

  COLOR=$(echo "$COLORS" | awk -v i=$((IDX + 1)) '{print $i}')

  NAME="focus.s$IDX"
  sketchybar --add item "$NAME" left \
             --set "$NAME" icon.drawing=off \
                           label.drawing=off \
                           width="$W" \
                           padding_left=0 \
                           padding_right=1 \
                           background.drawing=on \
                           background.color="$COLOR" \
                           background.corner_radius=3 \
                           background.height=6 \
             --move "$NAME" after "$PREV" 2>/dev/null

  PREV="$NAME"
  IDX=$((IDX + 1))
done

H=$((TOTAL / 3600))
M=$(((TOTAL % 3600) / 60))
if [ "$TOTAL" -eq 0 ]; then
  LABEL="0m"
elif [ "$H" -gt 0 ]; then
  LABEL="${H}h${M}m"
else
  LABEL="${M}m"
fi

sketchybar --set focus icon.drawing=off label="$LABEL" padding_left=6 padding_right=2

TOTAL=${TOTAL:-0}
MOVE_SECS=${MOVE_SECS:-28800}

# Move CPU/RAM when today's focus reaches 8h
if [ "$TOTAL" -ge "$MOVE_SECS" ]; then
  sketchybar --set cpu position=right \
             --set ram position=right
  sketchybar --move cpu before mood 2>/dev/null
  sketchybar --move ram after cpu 2>/dev/null
  sketchybar --move chevron after "$PREV" 2>/dev/null
  sketchybar --move front_app after chevron 2>/dev/null
else
  sketchybar --set cpu position=left \
             --set ram position=left
  sketchybar --move cpu after "$PREV" 2>/dev/null
  sketchybar --move ram after cpu 2>/dev/null
  sketchybar --move chevron after ram 2>/dev/null
  sketchybar --move front_app after chevron 2>/dev/null
fi

python3 "$PLUGIN_DIR/timer.py" stats
