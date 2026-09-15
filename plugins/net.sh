#!/bin/sh

# Network speed — collapsed by default (icon only).
# Click icon -> expand and poll live ↓/↑ speeds.
# Click again -> collapse and stop polling.

CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
CACHE_FILE="$CACHE_DIR/net_bytes"
STATE_FILE="$CACHE_DIR/net_expanded"
mkdir -p "$CACHE_DIR"

is_expanded() {
  [ "$(cat "$STATE_FILE" 2>/dev/null)" = "1" ]
}

set_expanded() {
  echo "$1" > "$STATE_FILE"
}

human() {
  B="$1"
  case "$B" in
    ''|*[!0-9]*) B=0 ;;
  esac
  if [ "$B" -ge 1048576 ]; then
    awk -v b="$B" 'BEGIN { printf "%.1fM", b / 1048576 }'
  elif [ "$B" -ge 1024 ]; then
    awk -v b="$B" 'BEGIN { printf "%.0fK", b / 1024 }'
  else
    echo "${B}B"
  fi
}

measure() {
  IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')
  IFACE="${IFACE:-en0}"

  BYTES=$(netstat -ibn | awk -v iface="$IFACE" '
    $1 == iface && $1 !~ /\*/ {
      rx=$7; tx=$10
    }
    END { print rx+0, tx+0 }
  ')
  RX=${BYTES%% *}
  TX=${BYTES##* }
  NOW=$(date +%s)

  if [ -f "$CACHE_FILE" ]; then
    read -r PREV_RX PREV_TX PREV_T < "$CACHE_FILE"
    DT=$((NOW - PREV_T))
    if [ "$DT" -gt 0 ]; then
      DOWN=$(( (RX - PREV_RX) / DT ))
      UP=$(( (TX - PREV_TX) / DT ))
    else
      DOWN=0
      UP=0
    fi
  else
    DOWN=0
    UP=0
  fi

  echo "$RX $TX $NOW" > "$CACHE_FILE"
  echo "↓$(human "$DOWN") ↑$(human "$UP")"
}

collapse() {
  set_expanded 0
  sketchybar --set net label.drawing=off update_freq=0 label=""
}

expand() {
  set_expanded 1
  # Reset baseline so the first tick after expand is clean
  rm -f "$CACHE_FILE"
  LABEL="$(measure)"
  sketchybar --set net label.drawing=on update_freq=2 label="$LABEL"
}

case "$SENDER" in
  mouse.clicked)
    if is_expanded; then
      collapse
    else
      expand
    fi
    ;;
  *)
    # Periodic update only while expanded
    if is_expanded; then
      sketchybar --set net label="$(measure)" label.drawing=on
    else
      collapse
    fi
    ;;
esac
