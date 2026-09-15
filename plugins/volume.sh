#!/bin/sh

# Volume icon + light horizontal popup slider
# - Click icon: toggle popup (auto-closes)
# - Drag slider: live-updates system volume + side icons/percent
# - mouse.exited.global: close popup

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
MONITOR_PID="$CACHE_DIR/volume_monitor.pid"
mkdir -p "$CACHE_DIR"

volume_icon() {
  VOL="$1"
  case "$VOL" in
    [6-9][0-9]|100) echo "󰕾" ;;
    [3-5][0-9]) echo "󰖀" ;;
    [1-9]|[1-2][0-9]) echo "󰕿" ;;
    *) echo "󰖁" ;;
  esac
}

clamp_vol() {
  VOL="$1"
  VOL=$(printf "%.0f" "$VOL" 2>/dev/null || echo 0)
  [ "$VOL" -lt 0 ] && VOL=0
  [ "$VOL" -gt 100 ] && VOL=100
  echo "$VOL"
}

update_display() {
  VOL="$(clamp_vol "$1")"
  ICON=$(volume_icon "$VOL")
  # Left icon follows level; right shows percent
  sketchybar --set volume icon="$ICON" label="${VOL}%" \
             --set volume.slider slider.percentage="$VOL" \
             --set volume.low icon="$ICON" \
             --set volume.percent label="${VOL}%"
}

apply_volume() {
  VOL="$(clamp_vol "$1")"
  osascript -e "set volume output volume $VOL" >/dev/null 2>&1
  update_display "$VOL"
}

stop_monitor() {
  if [ -f "$MONITOR_PID" ]; then
    kill "$(cat "$MONITOR_PID")" 2>/dev/null
    rm -f "$MONITOR_PID"
  fi
}

# Poll slider while popup is open so drag updates live
start_monitor() {
  stop_monitor
  (
    LAST=-1
    while true; do
      DRAWING=$(sketchybar --query volume 2>/dev/null | sed -n 's/.*"drawing":"\([^"]*\)".*/\1/p' | head -1)
      # Prefer python for reliable JSON if available
      PCT=$(python3 - <<'PY' 2>/dev/null
import json,subprocess
try:
  d=json.loads(subprocess.check_output(["sketchybar","--query","volume"]))
  if d.get("popup",{}).get("drawing")!="on":
    print("CLOSED"); raise SystemExit
  s=json.loads(subprocess.check_output(["sketchybar","--query","volume.slider"]))
  print(int(float(s.get("slider",{}).get("percentage",0))))
except Exception:
  print("CLOSED")
PY
)
      if [ "$PCT" = "CLOSED" ]; then
        break
      fi
      if [ "$PCT" != "$LAST" ]; then
        apply_volume "$PCT"
        LAST=$PCT
        # Refresh auto-close while interacting
        "$PLUGIN_DIR/popup_autoclose.sh" volume 2
      fi
      sleep 0.08
    done
    rm -f "$MONITOR_PID"
  ) >/dev/null 2>&1 &
  echo $! > "$MONITOR_PID"
}

open_popup() {
  sketchybar --set volume popup.drawing=on
  "$PLUGIN_DIR/popup_autoclose.sh" volume 3
  start_monitor
}

close_popup() {
  stop_monitor
  sketchybar --set volume popup.drawing=off
}

case "$SENDER" in
  volume_change)
    update_display "$INFO"
    ;;
  mouse.exited.global)
    close_popup
    ;;
  mouse.clicked)
    if [ "$NAME" = "volume.slider" ] && [ -n "$PERCENTAGE" ]; then
      apply_volume "$PERCENTAGE"
      "$PLUGIN_DIR/popup_autoclose.sh" volume 2
    elif [ "$NAME" = "volume" ]; then
      DRAWING=$(python3 - <<'PY' 2>/dev/null
import json,subprocess
print(json.loads(subprocess.check_output(["sketchybar","--query","volume"])).get("popup",{}).get("drawing","off"))
PY
)
      if [ "$DRAWING" = "on" ]; then
        close_popup
      else
        open_popup
      fi
    fi
    ;;
  *)
    VOL=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
    update_display "${VOL:-0}"
    ;;
esac
