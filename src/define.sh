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
    nvidia_egl=""
    for lib in /usr/lib/*/libEGL_nvidia.so.0 /usr/lib/libEGL_nvidia.so.0; do
      [ -e "$lib" ] && { nvidia_egl="y"; break; }
    done
    nvidia_node=""
    mesa_node=""
    for node in /dev/dri/renderD*; do
      [ -c "$node" ] || continue
      if ! { exec 3<"$node"; } 2>/dev/null; then
        info "Render node $node is not accessible (is the \"c 226:* rwm\" device cgroup rule set?); skipping."
        continue
      fi
      exec 3<&-
      vid=""
      [ -r "/sys/class/drm/$(basename "$node")/device/vendor" ] && vid=$(cat "/sys/class/drm/$(basename "$node")/device/vendor")
      if [ "$vid" = "0x10de" ]; then
        [ -z "$nvidia_node" ] && nvidia_node="$node"
      else
        [ -z "$mesa_node" ] && mesa_node="$node"
      fi
    done
    if [ -n "$nvidia_node" ] && [ -n "$nvidia_egl" ]; then
      kms=""
      for card in "/sys/class/drm/$(basename "$nvidia_node")/device/drm/"card*; do
        [ -e "$card" ] && { kms="y"; break; }
      done
      if [ -n "$kms" ]; then
        RENDERNODE="$nvidia_node"
      else
        info "Nvidia GPU found at $nvidia_node but the host has nvidia-drm modeset disabled; set \"options nvidia_drm modeset=1\" on the host to use it."
      fi
    fi
    [ -z "${RENDERNODE:-}" ] && [ -n "$mesa_node" ] && RENDERNODE="$mesa_node"
    if [ -z "${RENDERNODE:-}" ] && [ -n "$nvidia_node" ] && [ -z "$nvidia_egl" ]; then
      info "Nvidia GPU found but its EGL userspace is absent; run with \"--gpus all\" and NVIDIA_DRIVER_CAPABILITIES=all to use it."
    fi
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
