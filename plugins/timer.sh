#!/bin/sh
# Original timer gestures are preserved; classification lives in timer_category.
PLUGIN_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
exec python3 "$PLUGIN_DIR/timer.py" event
