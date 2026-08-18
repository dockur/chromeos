#!/usr/bin/env bash
set -Eeuo pipefail

: "${PLATFORM:="x64"}"
: "${APP:="ChromeOS Flex"}"
: "${SUPPORT:="https://github.com/dockur/chromeos"}"

: "${AUDIO:="N"}"
: "${LOSSY:="N"}"
: "${SHUTDOWN:="Y"}"
: "${TIMEOUT:="105"}"
: "${RAM_MINIMUM:="2G"}"
: "${BOOT_MODE:="uefi"}"
: "${RAM_MINIMUM:="2G"}"
: "${DISK_MINIMUM:="16G"}"
: "${MOUSE:="usb-tablet"}"

cd /run

. start.sh      # Startup hook
. utils.sh      # Load functions
. init.sh       # Initialize system
. memory.sh     # Check memory
. server.sh     # Start webserver
. download.sh   # Load functions
. define.sh     # ChromeOS parameters
. install.sh    # Download the image
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. audio.sh      # Initialize audio
. network.sh    # Initialize network
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. power.sh      # Configure shutdown
. balloon.sh    # Initialize ballooning
. config.sh     # Configure arguments
. finish.sh     # Finish initialization

trap - ERR

cmd=(qemu-system-x86_64)
version=$("${cmd[@]}" --version | awk 'NR==1 { print $4 }')
info "Booting $APP using QEMU v$version..." && echo

if ! enabled "$SHUTDOWN"; then
  exec "${cmd[@]}" ${ARGS:+ $ARGS}
fi

if ! interactive; then
  "${cmd[@]}" ${ARGS:+ $ARGS} &
else
  startConsole
  startQemu "${cmd[@]}" ${ARGS:+ $ARGS}
fi

pid=$!
rc=0

wait "$pid" || rc=$?
[ -f "$QEMU_END" ] && exit "$rc"

sleep 1 & wait $!
finish "$rc"
