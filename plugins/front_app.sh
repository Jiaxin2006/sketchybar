#!/bin/sh

# Front app label + native app menu popup
# Uses the cached app name from front_app_switched (not "frontmost"),
# because clicking SketchyBar often steals frontmost and breaks menu reads
# for apps like Typora.

CACHE_DIR="${TMPDIR:-/tmp}/sketchybar"
MENU_CACHE="$CACHE_DIR/front_app_menus"
APP_CACHE="$CACHE_DIR/front_app_name"
MAX_MENUS=12
MENUS_BIN="${CONFIG_DIR:-$HOME/.config/sketchybar}/helpers/menus/bin/menus"

mkdir -p "$CACHE_DIR"

close_menu_popup() {
  sketchybar --set front_app popup.drawing=off
}

current_app_name() {
  if [ -f "$APP_CACHE" ]; then
    cat "$APP_CACHE"
    return
  fi
  # Fallback: label currently shown on the item
  sketchybar --query front_app 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("label",{}).get("value",""))' 2>/dev/null
}

# List menus for a *named* process (reliable for Typora / Electron apps)
list_menus_for_app() {
  APP="$1"
  [ -z "$APP" ] && return
  osascript - "$APP" <<'EOF' 2>/dev/null
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    if not (exists process appName) then return ""
    tell process appName
      set out to ""
      try
        repeat with mi in menu bar items of menu bar 1
          try
            set n to name of mi
            -- Skip Apple menu; keep app menu + File/Edit/...
            if n is not missing value and n is not "" and n is not "Apple" then
              if out is "" then
                set out to n
              else
                set out to out & linefeed & n
              end if
            end if
          end try
        end repeat
      end try
      return out
    end tell
  end tell
end run
EOF
}

list_menus() {
  APP="$(current_app_name)"
  OUT="$(list_menus_for_app "$APP")"
  # If named lookup failed, last resort: frontmost (may be wrong after click)
  if [ -z "$OUT" ]; then
    OUT="$(list_menus_for_app "$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)")"
  fi
  echo "$OUT"
}

open_menu_by_name() {
  TITLE="$1"
  APP="$(current_app_name)"
  [ -z "$TITLE" ] || [ -z "$APP" ] && return

  # Activate target app so its menu bar is live, then click the item by name
  osascript - "$APP" "$TITLE" <<'EOF' 2>/dev/null
on run argv
  set appName to item 1 of argv
  set menuTitle to item 2 of argv
  try
    tell application appName to activate
  end try
  delay 0.05
  tell application "System Events"
    if not (exists process appName) then return
    tell process appName
      set frontmost to true
      click menu bar item menuTitle of menu bar 1
    end tell
  end tell
end run
EOF
}

open_menu_by_id() {
  ID="$1"
  TITLE="$(sed -n "${ID}p" "$MENU_CACHE" 2>/dev/null)"
  close_menu_popup
  # Prefer name-based click on the cached app (works for Typora)
  open_menu_by_name "$TITLE"
}

cache_menus_for_front_app() {
  MENU_LIST="$(list_menus)"
  printf "%s\n" "$MENU_LIST" > "$MENU_CACHE"
}

populate_and_toggle_popup() {
  cache_menus_for_front_app
  MENU_LIST="$(cat "$MENU_CACHE" 2>/dev/null)"

  i=1
  while [ "$i" -le "$MAX_MENUS" ]; do
    sketchybar --set "app_menu.$i" drawing=off label=""
    i=$((i + 1))
  done

  IDX=1
  while IFS= read -r TITLE || [ -n "$TITLE" ]; do
    [ -z "$TITLE" ] && continue
    [ "$IDX" -gt "$MAX_MENUS" ] && break
    sketchybar --set "app_menu.$IDX" label="$TITLE" drawing=on
    IDX=$((IDX + 1))
  done <<EOF
$MENU_LIST
EOF

  if [ "$IDX" -eq 1 ]; then
    APP="$(current_app_name)"
    sketchybar --set app_menu.1 \
      label="无法读取「${APP:-?}」的菜单" \
      drawing=on
  fi

  sketchybar --set front_app popup.drawing=toggle
}

case "$NAME" in
  app_menu.*)
    ID="${NAME#app_menu.}"
    open_menu_by_id "$ID"
    ;;
  front_app)
    case "$SENDER" in
      front_app_switched)
        # Persist exact app name from SketchyBar event
        printf "%s" "$INFO" > "$APP_CACHE"
        sketchybar --set "$NAME" label="$INFO"
        close_menu_popup
        cache_menus_for_front_app
        ;;
      mouse.clicked)
        populate_and_toggle_popup
        ;;
      mouse.exited.global)
        close_menu_popup
        ;;
    esac
    ;;
esac
