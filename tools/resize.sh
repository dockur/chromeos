#!/usr/bin/env bash
# Expands ChromeOS Flex's STATE partition (and its ext4 filesystem) to fill any
# unallocated space at the end of /storage/flex/data.img. Run from the host after
# stopping the container if you have increased DISK_SIZE on an existing install.
set -Eeuo pipefail

STORAGE="${1:-./chromeos}"
IMG="$STORAGE/flex/data.img"

if [ ! -f "$IMG" ]; then
  echo "error: $IMG not found" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

for cmd in sgdisk losetup e2fsck resize2fs lsof; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd not installed (apt install gdisk e2fsprogs util-linux lsof)" >&2; exit 1; }
done

if lsof "$IMG" >/dev/null 2>&1; then
  echo "error: $IMG is locked, stop the container first" >&2
  exit 1
fi

p1_start=$(sgdisk -i 1 "$IMG" 2>/dev/null | awk '/First sector/ {print $3}')
p1_name=$(sgdisk -i 1 "$IMG" 2>/dev/null | awk -F"'" '/Partition name/ {print $2}')
p1_guid=$(sgdisk -i 1 "$IMG" 2>/dev/null | awk '/Partition unique GUID/ {print $4}')

if [ "$p1_name" != "STATE" ]; then
  echo "error: partition 1 is named '$p1_name', expected 'STATE' (is this a Flex disk?)" >&2
  exit 1
fi

disk_sectors=$(($(stat -c%s "$IMG") / 512))
p1_end_before=$(sgdisk -i 1 "$IMG" 2>/dev/null | awk '/Last sector/ {print $3}')
tail_unalloc=$((disk_sectors - p1_end_before - 33))

if [ "$tail_unalloc" -lt 2097152 ]; then
  echo "nothing to do: less than 1 GiB unallocated at end of disk ($((tail_unalloc*512/1024/1024)) MiB)"
  exit 0
fi

echo "before: STATE = $(((p1_end_before - p1_start + 1) * 512 / 1024 / 1024 / 1024)) GiB"
echo "growing to fill disk ($((disk_sectors * 512 / 1024 / 1024 / 1024)) GiB total)..."

sgdisk -e "$IMG" >/dev/null
sgdisk -d 1 "$IMG" >/dev/null
sgdisk -n "1:$p1_start:0" -t 1:0FC63DAF-8483-4772-8E79-3D69D8477DE4 -c 1:STATE -u "1:$p1_guid" "$IMG" >/dev/null

loop=$(losetup -Pf --show "$IMG")
trap 'losetup -d "$loop" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do [ -b "${loop}p1" ] && break; sleep 0.1; done
udevadm settle 2>/dev/null || true
if [ ! -b "${loop}p1" ]; then
  echo "error: partition node ${loop}p1 did not appear" >&2
  exit 1
fi
e2fsck -fy "${loop}p1" >/dev/null
resize2fs "${loop}p1" >/dev/null

p1_end_after=$(sgdisk -i 1 "$IMG" 2>/dev/null | awk '/Last sector/ {print $3}')
echo "after:  STATE = $(((p1_end_after - p1_start + 1) * 512 / 1024 / 1024 / 1024)) GiB"
echo "done. start the container."
