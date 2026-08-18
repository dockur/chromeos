#!/usr/bin/env bash
set -Eeuo pipefail

: "${TABLET:="Y"}"
: "${KEEP_AWAKE:="N"}"
: "${FORCE_HOST_CURSOR:="N"}"

# Show the browser's cursor over the noVNC canvas — ChromeOS hides its own cursor
# in touchscreen mode (which we are, since usb-tablet sends absolute coords).
CSS_MARKER='/* chromeos-flex */'
CSS_RULE='#noVNC_container, #noVNC_container * { cursor: default !important; }'
BASE_CSS='/usr/share/novnc/app/styles/base.css'

if [ -f "$BASE_CSS" ]; then

  sed -i "\|$CSS_MARKER|,+1d" "$BASE_CSS" 2>/dev/null || true

  if enabled "$TABLET" || enabled "$FORCE_HOST_CURSOR"; then
    printf '\n%s\n%s\n' "$CSS_MARKER" "$CSS_RULE" >> "$BASE_CSS"
  fi

fi

if enabled "$TABLET" && [ -x /run/mouse_fix.sh ]; then
  nohup /run/mouse_fix.sh >/dev/null 2>&1 &
  disown
else
  MOUSE="usb-mouse"
fi

if enabled "$KEEP_AWAKE" && [ -x /run/keep_awake.sh ]; then
  nohup /run/keep_awake.sh >/dev/null 2>&1 &
  disown
fi
