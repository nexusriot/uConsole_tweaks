#!/usr/bin/env bash
# Download and verify the official uConsole CM4 Raspberry Pi OS image (v2.1).
set -euo pipefail

URL="http://dl.clockworkpi.com/uConsole_CM4_v2.1_64bit.img.bz2"
EXPECTED_MD5="b14715f3fe2789ef8b40dded37c3bc63"
ARCHIVE="uConsole_CM4_v2.1_64bit.img.bz2"
IMG="uConsole_CM4_v2.1_64bit.img"

if [[ -f "$IMG" ]]; then
  echo "Image already exists: $IMG"
  exit 0
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "Downloading official image..."
  wget -c "$URL" -O "$ARCHIVE"
fi

echo "Verifying MD5..."
ACTUAL_MD5=$(md5sum "$ARCHIVE" | awk '{print $1}')
if [[ "$ACTUAL_MD5" != "$EXPECTED_MD5" ]]; then
  echo "MD5 mismatch! Expected $EXPECTED_MD5, got $ACTUAL_MD5" >&2
  exit 1
fi
echo "MD5 OK."

echo "Decompressing..."
bunzip2 "$ARCHIVE"

echo "Ready: $IMG"
echo "Flash with: sudo ./flash-sd.sh $IMG /dev/sdX"
