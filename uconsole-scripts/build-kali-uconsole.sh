#!/usr/bin/env bash
# Build a uConsole CM4-ready Kali Linux image from a stock Kali Raspberry Pi ARM64 image.
# Must run on an x86_64 Ubuntu 22.04/24.04 build PC as root.
#
# Usage: sudo ./build-kali-uconsole.sh <kali-raspberry-pi-arm64.img> [--4g]
set -euo pipefail

MOUNT=/mnt/uconsole_build
GROW_MB=4096
ENABLE_4G=0

usage() {
  echo "Usage: sudo $0 <kali-raspberry-pi-arm64.img> [--4g]" >&2
  exit 1
}

[[ $# -lt 1 ]] && usage
[[ "$(id -u)" -ne 0 ]] && { echo "Run as root." >&2; exit 1; }

SRC_IMG="$1"
[[ ! -f "$SRC_IMG" ]] && { echo "File not found: $SRC_IMG" >&2; exit 1; }

[[ "${2:-}" == "--4g" ]] && ENABLE_4G=1

OUT_IMG="${SRC_IMG%.img}-uconsole.img"
cp "$SRC_IMG" "$OUT_IMG"
echo "Working copy: $OUT_IMG"

echo "Growing image by ${GROW_MB} MB..."
dd if=/dev/zero bs=1M count=$GROW_MB >> "$OUT_IMG" status=none
parted "$OUT_IMG" --script resizepart 2 100%

mkdir -p "$MOUNT"
LOOPDEV=$(losetup -f --show -P "$OUT_IMG")
echo "Loop device: $LOOPDEV"

cleanup() {
  echo "Cleaning up..."
  umount "$MOUNT/dev/pts" 2>/dev/null || true
  umount "$MOUNT/dev"     2>/dev/null || true
  umount "$MOUNT/proc"    2>/dev/null || true
  umount "$MOUNT/sys"     2>/dev/null || true
  rm -f  "$MOUNT/usr/bin/qemu-aarch64-static"
  rm -f  "$MOUNT/root/.bash_history"
  umount "$MOUNT/boot"    2>/dev/null || true
  umount "$MOUNT"         2>/dev/null || true
  losetup -d "$LOOPDEV"   2>/dev/null || true
}
trap cleanup EXIT

e2fsck -f "${LOOPDEV}p2"
resize2fs "${LOOPDEV}p2"

mount "${LOOPDEV}p2" "$MOUNT"
mount "${LOOPDEV}p1" "$MOUNT/boot"

mount --bind /dev     "$MOUNT/dev"
mount --bind /sys     "$MOUNT/sys"
mount --bind /proc    "$MOUNT/proc"
mount --bind /dev/pts "$MOUNT/dev/pts"

cp /usr/bin/qemu-aarch64-static "$MOUNT/usr/bin/" 2>/dev/null || true

chr() { chroot "$MOUNT" /bin/bash -c "$*"; }

echo "Removing Kali Pi kernel..."
chr "apt-get remove -y kalipi-kernel kalipi-kernel-headers 2>/dev/null || true"

echo "Adding ClockworkPi APT repo..."
chr "wget -q -O- https://raw.githubusercontent.com/clockworkpi/apt/main/debian/KEY.gpg \
  | gpg --dearmor | tee /etc/apt/trusted.gpg.d/clockworkpi.gpg > /dev/null"

chr "echo 'deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main' \
  > /etc/apt/sources.list.d/clockworkpi.list"

chr "apt-get update"
chr "apt-get install -y uconsole-kernel-cm4-rpi"

cat > "$MOUNT/etc/apt/preferences.d/kalipi-kernel" <<'EOF'
Package: kalipi-kernel
Pin: release *
Pin-Priority: -1
EOF

cat > "$MOUNT/etc/apt/preferences.d/kalipi-kernel-headers" <<'EOF'
Package: kalipi-kernel-headers
Pin: release *
Pin-Priority: -1
EOF

echo "Configuring screen rotation..."
cat > "$MOUNT/etc/lightdm/setup.sh" <<'EOF'
#!/bin/bash
xrandr --output DSI-1 --rotate right
exit 0
EOF
chmod +x "$MOUNT/etc/lightdm/setup.sh"

sed -i 's|^#greeter-setup-script=.*|greeter-setup-script=/etc/lightdm/setup.sh|' \
  "$MOUNT/etc/lightdm/lightdm.conf" 2>/dev/null || true

# Also rotate for the kali user's X session
mkdir -p "$MOUNT/home/kali"
echo 'xrandr --output DSI-1 --rotate right' >> "$MOUNT/home/kali/.xprofile"

if [[ $ENABLE_4G -eq 1 ]]; then
  echo "Installing 4G module support..."
  chr "apt-get install -y pppoe uconsole-4g-util-cm4"
  cat > "$MOUNT/etc/modprobe.d/blacklist-qmi.conf" <<'EOF'
blacklist qmi_wwan
blacklist cdc_wdm
EOF
fi

echo "Done. Image ready: $OUT_IMG"
echo "Flash with: sudo ./flash-sd.sh $OUT_IMG /dev/sdX"
