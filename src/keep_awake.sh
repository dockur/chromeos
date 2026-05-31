#!/usr/bin/env bash
# Periodically inject a pause-key press into QEMU's HMP monitor to keep
# ChromeOS Flex's idle timer reset, preventing display sleep and S3 suspend
# (from which noVNC has no way to wake the guest).
while sleep 240; do
  printf 'sendkey pause\n' | timeout 2 nc -q 1 localhost 7100 >/dev/null 2>&1 || true
done
