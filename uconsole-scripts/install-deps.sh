#!/usr/bin/env bash
# Install build dependencies required on the Ubuntu x86_64 build PC.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

apt-get update
apt-get install -y \
  git p7zip-full bzip2 xz-utils wget curl \
  qemu-user-static binfmt-support \
  parted kpartx dosfstools e2fsprogs \
  coreutils util-linux \
  crossbuild-essential-arm64 bc bison flex libssl-dev make

echo "All build dependencies installed."
