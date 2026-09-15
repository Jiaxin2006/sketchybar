#!/bin/sh

# Mood picker (monochrome Nerd Font icons)
#
# === How to add / remove a mood ===
# 1) In sketchybarrc, add or delete a popup item, e.g.:
#      --add item mood.zzz popup.mood \
#      --set mood.zzz icon=󰒲 label.drawing=off \
#                       click_script="$PLUGIN_DIR/mood.sh"
# 2) In this file, add a matching case:
#      mood.zzz) set_mood "󰒲" ;;
# 3) sketchybar --reload
# Tip: verify icon names with the Nerd Fonts cheat sheet
#      https://www.nerdfonts.com/cheat-sheet
# Current icons (verified in Hack Nerd Font):
#   happy 󰱱  calm 󰱫  focus 󰓾  tired 󰒲  sad 󰱶  fire 󰈸  default 󰱴

PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
STATE_FILE="$CACHE_DIR/mood_state"
LOG_DIR="${HOME}/.config/sketchybar/data"
LOG_FILE="$LOG_DIR/mood.log"

mkdir -p "$CACHE_DIR" "$LOG_DIR"

DEFAULT_ICON="󰱴"

load_mood() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "$DEFAULT_ICON"
  fi
}

set_mood() {
  ICON="$1"
  echo "$ICON" > "$STATE_FILE"
  printf "%s\t%s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$ICON" >> "$LOG_FILE"
  sketchybar --set mood icon="$ICON" icon.font="Hack Nerd Font:Bold:14.0" popup.drawing=off
}

case "$NAME" in
  mood.happy)   set_mood "󰱱" ;;
  mood.calm)    set_mood "󰱫" ;;
  mood.focus)   set_mood "󰓾" ;;
  mood.tired)   set_mood "󰒲" ;;
  mood.sad)     set_mood "󰱶" ;;
  mood.fire)    set_mood "󰈸" ;;
  mood)
    case "$SENDER" in
      mouse.exited.global)
        sketchybar --set mood popup.drawing=off
        ;;
      mouse.clicked)
        DRAWING=$(python3 - <<'PY' 2>/dev/null
import json,subprocess
print(json.loads(subprocess.check_output(["sketchybar","--query","mood"])).get("popup",{}).get("drawing","off"))
PY
)
        if [ "$DRAWING" = "on" ]; then
          sketchybar --set mood popup.drawing=off
        else
          sketchybar --set mood popup.drawing=on
          "$PLUGIN_DIR/popup_autoclose.sh" mood 3
        fi
        ;;
      *)
        sketchybar --set mood icon="$(load_mood)" icon.font="Hack Nerd Font:Bold:14.0"
        ;;
    esac
    ;;
esac
