#!/usr/bin/env bash
# Activate the usb-tablet handler at runtime so QEMU's VNC server sends absolute
# coordinates. Without this, ps2-mouse wins handler-find order and VNC falls back
# to relative deltas, which ChromeOS Flex's pointer acceleration mishandles
# (first click works, subsequent clicks land off-target).
for _ in $(seq 1 60); do
  idx=$(printf 'info mice\n' | timeout 2 nc -q 1 localhost 7100 2>/dev/null | \
        sed -n 's/.*Mouse #\([0-9]\+\): QEMU HID Tablet.*/\1/p' | head -1)
  if [ -n "$idx" ]; then
    printf 'mouse_set %s\n' "$idx" | timeout 2 nc -q 1 localhost 7100 >/dev/null 2>&1
    exit 0
  fi
  sleep 1
done
