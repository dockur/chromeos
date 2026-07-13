#!/usr/bin/env bash
set -Eeuo pipefail

: "${LOSSY:="N"}"
: "${TABLET:="Y"}"
: "${BOOT_MODE:="uefi"}"
: "${FORCE_HOST_CURSOR:="Y"}"

BOOT_DESC=" ChromeOS Flex (${VERSION,,})"

gpu="${GPU:-}"
gpu_vendor=""

case "${gpu,,}" in
  ""|n|no|0|false|off) GPU="" ;;
  y|yes|1|true|on|auto) GPU="Y" ;;
  intel) GPU="Y"; gpu_vendor="0x8086" ;;
  amd) GPU="Y"; gpu_vendor="0x1002" ;;
  nvidia) GPU="Y"; gpu_vendor="0x10de" ;;
  *) info "Unknown GPU value \"$gpu\"; treating it as auto."; GPU="Y" ;;
esac

if [ -n "$GPU" ] && [ -z "${RENDERNODE:-}" ]; then
  compgen -G "/usr/lib/*/libEGL_nvidia.so.0" >/dev/null && nvidia_egl=1 || nvidia_egl=
  for node in /dev/dri/renderD*; do
    { exec 3<"$node"; } 2>/dev/null || continue
    exec 3<&-
    dev="/sys/class/drm/${node##*/}/device"
    vid=$(cat "$dev/vendor" 2>/dev/null)
    if [ -n "$gpu_vendor" ] && [ "$vid" != "$gpu_vendor" ]; then
      continue
    fi
    if [ "$vid" != "0x10de" ]; then
      : "${RENDERNODE:=$node}"
    elif [ -z "$nvidia_egl" ]; then
      info "Nvidia GPU at $node has no graphics capability; run the container with \"--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all\"."
    elif ! compgen -G "$dev/drm/card*" >/dev/null; then
      info "Nvidia GPU at $node needs nvidia-drm modeset=1 on the host; add \"options nvidia_drm modeset=1\" and reboot."
    else
      RENDERNODE="$node"; break
    fi
  done
fi

if [ -n "$GPU" ] && { [ -z "${RENDERNODE:-}" ] || [ ! -c "${RENDERNODE:-/dev/null}" ]; }; then
  info "No usable ${gpu_vendor:+$gpu }GPU render node found; falling back to software rendering."
  GPU=""
fi

if [ -n "$GPU" ]; then
  case "$(cat "/sys/class/drm/${RENDERNODE##*/}/device/vendor" 2>/dev/null)" in
    0x8086) gpu_name="Intel" ;;
    0x1002) gpu_name="AMD" ;;
    0x10de) gpu_name="Nvidia" ;;
    *) gpu_name="GPU" ;;
  esac
  info "Hardware rendering on $gpu_name render node $RENDERNODE."
fi

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
