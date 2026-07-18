#!/usr/bin/env bash
set -Eeuo pipefail

: "${VERSION:="stable"}"
: "${MANIFEST_URL:="https://dl.google.com/dl/edgedl/chromeos/recovery/cloudready_recovery2.json"}"

VERSION_LC="${VERSION,,}"
VERSION_FILTER=""

# VERSION can be a channel name (stable/beta/ltc/ltr) or a direct image URL.
if [[ "$VERSION_LC" =~ ^https?:// ]]; then
  url="$VERSION"
  VERSION_LC="custom"
else
  case "$VERSION_LC" in
    stable) VERSION_FILTER="STABLE" ;;
    ltc) VERSION_FILTER="LTC" ;;
    ltr) VERSION_FILTER="LTR" ;;
    beta) VERSION_FILTER="BETA" ;;
    *) error "Unknown VERSION=$VERSION (use: stable, ltc, ltr, beta, or a direct URL)" && exit 64 ;;
  esac
fi

FLEX_DIR="$STORAGE/flex"
DATA_IMG="$FLEX_DIR/data.img"

if ! makeDir "$FLEX_DIR"; then
  error "Failed to create directory \"$FLEX_DIR\"!" && exit 33
fi

# A valid ChromeOS GPT layout signals that Flex is already installed.
isInstalledDisk() {
  local table

  [ -f "$DATA_IMG" ] && [ -s "$DATA_IMG" ] || return 1

  dd if="$DATA_IMG" bs=512 skip=1 count=1 2>/dev/null |
    head -c 8 |
    grep -q "EFI PART" || return 1

  table=$(sfdisk -d "$DATA_IMG" 2>/dev/null) || return 1

  grep -Fq 'name="STATE"' <<< "$table" || return 1
  grep -Fq 'name="KERN-A"' <<< "$table" || return 1
  grep -Fq 'name="ROOT-A"' <<< "$table" || return 1
  grep -Fq 'name="EFI-SYSTEM"' <<< "$table" || return 1

  return 0
}

if isInstalledDisk; then

  # Toggle /syslinux/default.cfg between chromeos-vhd (verified) and chromeos-hd (rw rootfs) via mtools — no mount/loop/SYS_ADMIN needed.
  if [[ "${DEV_MODE:-}" =~ ^[YyNn] ]]; then
    set +e
    efi_start=$(sfdisk -d "$DATA_IMG" 2>/dev/null | awk -F'[ =,]+' '/EFI-SYSTEM/ {for(i=1;i<=NF;i++) if($i=="start") print $(i+1)}')
    if [ -n "$efi_start" ]; then
      efi_off=$((efi_start * 512))
      tmp=$(mktemp)
      mtype -i "$DATA_IMG@@$efi_off" ::/syslinux/default.cfg > "$tmp" 2>/dev/null
      if [ -s "$tmp" ]; then
        if [[ "${DEV_MODE:-}" =~ ^[Yy] ]] && grep -q 'chromeos-vhd' "$tmp"; then
          sed -i 's|chromeos-vhd|chromeos-hd|g' "$tmp"
          mcopy -o -i "$DATA_IMG@@$efi_off" "$tmp" ::/syslinux/default.cfg 2>/dev/null && \
            info "DEV_MODE=Y: switched boot default to chromeos-hd.A"
        elif [[ "${DEV_MODE:-}" =~ ^[Nn] ]] && grep -q 'chromeos-hd' "$tmp"; then
          sed -i 's|chromeos-hd|chromeos-vhd|g' "$tmp"
          mcopy -o -i "$DATA_IMG@@$efi_off" "$tmp" ::/syslinux/default.cfg 2>/dev/null && \
            info "DEV_MODE=N: switched boot default to chromeos-vhd.A"
        fi
      fi
      rm -f "$tmp"
    fi
    set -e
  fi

  info "Booting ChromeOS Flex from data disk."
  BOOT="none"
  STORAGE="$FLEX_DIR"
  return 0
fi

if [ -d "/boot.img" ]; then
  error "The bind /boot.img maps to a file that does not exist!" && exit 65
fi

if [ -f "/boot.img" ] && [ -s "/boot.img" ]; then
  info "Using custom ChromeOS image from /boot.img"
  BOOT="/boot.img"
  STORAGE="$FLEX_DIR"
  BOOT_MODE="uefi"
  BOOT_DESC=" ChromeOS Flex (custom)"
  return 0
fi

if [ -d "$FLEX_DIR/boot.img" ]; then
  error "The path $FLEX_DIR/boot.img is a directory instead of an image file!" && exit 65
fi

if [ -f "$FLEX_DIR/boot.img" ] && [ -s "$FLEX_DIR/boot.img" ]; then
  info "Reusing existing installer at $FLEX_DIR/boot.img"
  BOOT="$FLEX_DIR/boot.img"
  STORAGE="$FLEX_DIR"
  BOOT_MODE="uefi"
  return 0
fi

zipsize="0"

if [ -n "$VERSION_FILTER" ]; then
  info "Fetching ChromeOS Flex manifest ($VERSION_LC channel)..."
  html "Fetching manifest..."

  rc=0
  reason=""
  log=$(mktemp)
  manifest="$FLEX_DIR/manifest.json"

  rm -f "$manifest"

  {
    LC_ALL=C wget "$MANIFEST_URL" -O "$manifest" --no-verbose --timeout=30 \
      --no-http-keep-alive --output-file="$log"
    rc=$?
  } || :

  if (( rc != 0 )); then
    reason=$(sed -n \
      -e 's/^wget: //p' \
      -e 's/^[0-9-]\{10\} [0-9:]\{8\} ERROR //p' \
      "$log" | tail -n 1)
  fi

  rm -f "$log"

  if (( rc == 3 )); then
    error "Failed to download $MANIFEST_URL because the file could not be written (disk full?)."
    exit 60
  elif (( rc != 0 )); then
    if [ -n "$reason" ]; then
      error "Failed to download $MANIFEST_URL: ${reason%.}."
    else
      error "Failed to download $MANIFEST_URL with exit status $rc."
    fi
    exit 60
  fi

  if [ ! -s "$manifest" ]; then
    error "Manifest is empty!" && exit 60
  fi

  url=$(jq -r --arg c "$VERSION_FILTER" '
    [ .[] | select(.channel == $c and (.url // "") != "") ]
    | sort_by(.version | split(".") | map(tonumber? // 0))
    | last | .url // empty
  ' "$manifest" 2>/dev/null || echo "")

  if [ -z "$url" ]; then
    error "No ChromeOS Flex image found for channel \"$VERSION_FILTER\"" && exit 60
  fi

  version=$(jq -r --arg c "$VERSION_FILTER" '
    [ .[] | select(.channel == $c) ]
    | sort_by(.version | split(".") | map(tonumber? // 0))
    | last | .version // "unknown"
  ' "$manifest")

  zipsize=$(jq -r --arg c "$VERSION_FILTER" '
    [ .[] | select(.channel == $c) ]
    | sort_by(.version | split(".") | map(tonumber? // 0))
    | last | .zipfilesize // 0
  ' "$manifest")

  info "Selected ChromeOS Flex $version ($VERSION_LC), $(numfmt --to=iec --suffix=B "${zipsize:-0}") download"
else
  version="custom"
  info "Downloading custom ChromeOS image from $url"
fi

base="$(basename "${url%%\?*}")"
zip_dest="$FLEX_DIR/$base"

progress=()
output=""

# Use Wget's progress bar in a terminal and progress.sh in container logs.
if [ -t 1 ]; then
  progress=( --show-progress --progress=bar:noscroll )
else
  output="log"
fi

msg="Downloading ChromeOS Flex $version"
html "$msg..."

rc=0
reason=""
log=$(mktemp)

info "Downloading $base..."

rm -f "$zip_dest"
/run/progress.sh "$zip_dest" "${zipsize:-0}" "$msg ([P])..." "$output" &

{
  LC_ALL=C wget "$url" -O "$zip_dest" --continue --no-verbose --timeout=30 \
    --no-http-keep-alive "${progress[@]}" \
    --output-file="$log"
  rc=$?
} || :

fKill "progress.sh"

if (( rc != 0 )); then
  reason=$(sed -n \
    -e 's/^wget: //p' \
    -e 's/^[0-9-]\{10\} [0-9:]\{8\} ERROR //p' \
    "$log" | tail -n 1)
fi

rm -f "$log"

if (( rc == 3 )); then
  error "Failed to download $url because the file could not be written (disk full?)."
  exit 60
elif (( rc != 0 )); then
  if [ -n "$reason" ]; then
    error "Failed to download $url: ${reason%.}."
  else
    error "Failed to download $url with exit status $rc."
  fi
  exit 60
fi

if [ ! -s "$zip_dest" ]; then
  error "Failed to download $url: the downloaded file is empty."
  exit 60
fi

# Catch silent truncation: a valid Flex recovery zip is always >1GB; <100MB means CDN error page or partial download.
if ! actual_size=$(stat -c%s "$zip_dest"); then
  error "Failed to determine downloaded file size: $zip_dest"
  exit 60
fi

if [ "$actual_size" -lt 100000000 ]; then
  error "Downloaded file is suspiciously small ($actual_size bytes)"
  exit 60
fi

html "Download finished successfully..."

info "Extracting $base..."
html "Extracting image..."

tmp="$FLEX_DIR/extract"
rm -rf "$tmp"
mkdir -p "$tmp"

extract_size=$(7z l -slt "$zip_dest" 2>/dev/null |
  awk -F' = ' '/^Size = [0-9]+$/ && $2 > max { max = $2 } END { print max + 0 }')

/run/progress.sh "$tmp" "${extract_size:-0}" "Extracting image ([P])..." &

rc=0
{ 7z x -y "$zip_dest" -o"$tmp" > /dev/null; rc=$?; } || :

fKill "progress.sh"

if (( rc != 0 )); then
  rm -rf "$tmp"
  error "Failed to extract $base" && exit 32
fi

img=$(find "$tmp" -type f -iname "*.bin" -print -quit)

if [ ! -s "$img" ]; then
  rm -rf "$tmp"
  error "Could not find ChromeOS Flex image in archive" && exit 32
fi

mv "$img" "$FLEX_DIR/boot.img"
rm -rf "$tmp"
rm -f "$zip_dest"

setOwner "$FLEX_DIR/boot.img" || warn "failed to set owner on installer image"

BOOT_MODE="uefi"
BOOT="$FLEX_DIR/boot.img"
STORAGE="$FLEX_DIR"
BOOT_DESC=" ChromeOS Flex $version"

info "ChromeOS Flex installer ready at $BOOT"
return 0
