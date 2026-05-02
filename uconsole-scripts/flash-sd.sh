#!/usr/bin/env bash
# Safely flash a uConsole image to a microSD card.
# Unmounts all partitions first and requires explicit confirmation.
#
# Usage: sudo ./flash-sd.sh <image.img> <device>
#   e.g. sudo ./flash-sd.sh kali-uconsole.img /dev/sdb
#        sudo ./flash-sd.sh kali-uconsole.img /dev/mmcblk0
set -euo pipefail

[[ "$(id -u)" -ne 0 ]] && { echo "Run as root." >&2; exit 1; }
[[ $# -ne 2 ]] && { echo "Usage: sudo $0 <image.img> <device>" >&2; exit 1; }

IMG="$1"
DEV="$2"

[[ ! -f "$IMG" ]] && { echo "Image not found: $IMG" >&2; exit 1; }
[[ ! -b "$DEV" ]] && { echo "Not a block device: $DEV" >&2; exit 1; }

# Safety: refuse if the device looks like a system disk
SYS_DISK=$(lsblk -ndo PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null || true)
BARE_DEV=$(basename "$DEV")
if [[ "$BARE_DEV" == "$SYS_DISK" ]]; then
  echo "ERROR: $DEV appears to be your system disk. Aborting." >&2
  exit 1
fi

IMG_SIZE=$(stat -c%s "$IMG")
DEV_SIZE=$(blockdev --getsize64 "$DEV")

if [[ $IMG_SIZE -gt $DEV_SIZE ]]; then
  echo "ERROR: Image ($((IMG_SIZE / 1024 / 1024)) MB) is larger than device ($((DEV_SIZE / 1024 / 1024)) MB)." >&2
  exit 1
fi

echo "========================================"
echo " uConsole SD flash"
echo "========================================"
echo "  Image : $IMG  ($((IMG_SIZE / 1024 / 1024)) MB)"
echo "  Device: $DEV  ($((DEV_SIZE / 1024 / 1024)) MB)"
echo ""
lsblk "$DEV"
echo ""
echo "WARNING: This will ERASE ALL DATA on $DEV."
read -r -p "Type YES to continue: " CONFIRM
[[ "$CONFIRM" != "YES" ]] && { echo "Aborted."; exit 0; }

# Unmount any mounted partitions on the device
echo "Unmounting partitions..."
umount "${DEV}"?* 2>/dev/null || true
umount "${DEV}p"* 2>/dev/null || true

echo "Writing image (this may take several minutes)..."
dd if="$IMG" of="$DEV" bs=8M status=progress conv=fsync
sync

echo ""
echo "Flash complete. Remove and insert the microSD into the uConsole."
echo "Default credentials:"
echo "  Raspberry Pi OS : cpi / cpi"
echo "  Kali            : kali / kali"
echo "  Parrot          : parrot / parrot"
