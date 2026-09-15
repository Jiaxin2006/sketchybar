#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-$HOME/.config/sketchybar}"
if [ "$SOURCE_DIR" = "$(cd "$TARGET_DIR" 2>/dev/null && pwd || true)" ]; then
  echo 'Already running from the configuration directory.'
  exit 0
fi
for command in python3 sketchybar; do
  command -v "$command" >/dev/null || { echo "Missing dependency: $command" >&2; exit 1; }
done
python3 -c 'import sys; assert sys.version_info >= (3,9), "Python 3.9+ required"'
if [ -e "$TARGET_DIR" ]; then
  BACKUP_DIR="${TARGET_DIR}.backup.$(date +%Y%m%d-%H%M%S).$$"
  cp -R "$TARGET_DIR" "$BACKUP_DIR"
  echo "Backup: $BACKUP_DIR"
fi
mkdir -p "$TARGET_DIR/plugins" "$TARGET_DIR/helpers/menus"
# Copy engine first so the timer wrapper never refers to a missing file.
cp "$SOURCE_DIR/plugins/timer.py" "$TARGET_DIR/plugins/timer.py"
cp "$SOURCE_DIR"/plugins/*.sh "$TARGET_DIR/plugins/"
cp "$SOURCE_DIR/helpers/menus/menus.c" "$SOURCE_DIR/helpers/menus/makefile" "$TARGET_DIR/helpers/menus/"
cp "$SOURCE_DIR/sketchybarrc" "$TARGET_DIR/sketchybarrc"
chmod +x "$TARGET_DIR/sketchybarrc" "$TARGET_DIR"/plugins/*.sh
printf 'Installed: %s\nReload with: sketchybar --reload\n' "$TARGET_DIR"
