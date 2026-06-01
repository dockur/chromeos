#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP:="ChromeOSFlex"}"
: "${PLATFORM:="x64"}"
: "${SUPPORT:="https://github.com/forkymcforkface/chromeos"}"
: "${VERSION:="stable"}"

BOOT_DESC=" ChromeOS Flex (${VERSION,,})"

: "${BOOT_MODE:="uefi"}"

if [[ "${GPU:-}" =~ ^[Yy] ]]; then
  if [ -z "${RENDERNODE:-}" ]; then
    for node in /dev/dri/renderD*; do
      [ -c "$node" ] || continue
      pci=$(readlink -f "/sys/class/drm/$(basename "$node")/device" 2>/dev/null)
      if [ -n "$pci" ] && [ -r "$pci/vendor" ]; then
        vid=$(cat "$pci/vendor")
        # Nvidia's proprietary EGL fails QEMU's egl-headless init; skip and try the next node.
        if [ "$vid" = "0x10de" ]; then
          info "Skipping Nvidia render node $node (egl-headless requires Intel/AMD)."
          continue
        fi
      fi
      if ! { exec 3<"$node"; } 2>/dev/null; then
        info "Render node $node is not accessible (is the \"c 226:* rwm\" device cgroup rule set?); skipping."
        continue
      fi
      exec 3<&-
      RENDERNODE="$node"
      break
    done
  fi
  if [ -z "${RENDERNODE:-}" ] || [ ! -c "${RENDERNODE:-/dev/null}" ]; then
    info "GPU=Y requested but no usable render node found; falling back to software rendering."
    GPU=""
  fi
fi

: "${FORCE_HOST_CURSOR:="Y"}"
: "${LOSSY:="N"}"
: "${TABLET:="Y"}"

LOSSY_OPT=""
[[ "${LOSSY^^}" =~ ^Y ]] && LOSSY_OPT=",lossy=on"
export LOSSY_OPT

# Show the browser's cursor over the noVNC canvas — ChromeOS hides its own cursor in touchscreen mode (which we are, since usb-tablet sends absolute coords).
CSS_MARKER='/* chromeos-flex */'
CSS_RULE='#noVNC_container, #noVNC_container * { cursor: default !important; }'
BASE_CSS='/usr/share/novnc/app/styles/base.css'

if [ -f "$BASE_CSS" ]; then
  sed -i "\|$CSS_MARKER|,+1d" "$BASE_CSS" 2>/dev/null || true
  if [[ "${FORCE_HOST_CURSOR^^}" =~ ^[Yy] ]]; then
    printf '\n%s\n%s\n' "$CSS_MARKER" "$CSS_RULE" >> "$BASE_CSS"
  fi
fi

if [[ "${TABLET^^}" =~ ^Y ]] && [ -x /run/mouse_fix.sh ]; then
  nohup /run/mouse_fix.sh >/dev/null 2>&1 &
  disown
fi

if [[ "${KEEP_AWAKE:-N}" =~ ^[Yy] ]] && [ -x /run/keep_awake.sh ]; then
  nohup /run/keep_awake.sh >/dev/null 2>&1 &
  disown
fi

if [[ "${AUDIO:-N}" =~ ^[Yy] ]] && [ -x /run/audio.sh ]; then
  bash /run/audio.sh || true
  ARGUMENTS="${ARGUMENTS:-} -audiodev wav,id=snd,path=/run/audio.fifo,out.frequency=48000,out.channels=2,out.format=s16 -device intel-hda -device hda-output,audiodev=snd"
  export ARGUMENTS
fi
