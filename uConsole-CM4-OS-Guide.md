# uConsole CM4 (4 GB) — Custom OS Preparation Guide

This guide covers building **your own** OS image for the ClockworkPi **uConsole** with the **Raspberry Pi CM4** module (4 GB) for three distributions:

1. **Raspberry Pi OS** (the official base, built with `pi-gen`)
2. **Kali Linux** (ARM64, modified Raspberry Pi image)
3. **Parrot OS** (Security/Home, ARM64, modified Raspberry Pi image)

All three approaches share the same core idea: take a Raspberry Pi ARM64 image, swap in the **uConsole CM4 kernel** and supporting packages from ClockworkPi’s APT repo, then flash it to a microSD card.

---

## 0. What you need before starting

### Hardware
- uConsole with CM4 4 GB module assembled
- microSD card, **16 GB minimum** (32 GB recommended — Kali especially needs room)
- microSD reader on your build PC
- Spare 5 V / 3 A USB-C charger for first boot

### A Linux build PC (or VM)
You **cannot** properly do this from Windows or macOS — you need `losetup`, `chroot`, and an ARM64-capable build environment. Use **Ubuntu 22.04 / 24.04** (the official Clockwork build instructions assume Ubuntu).

Install build dependencies once:

```bash
sudo apt update
sudo apt install -y git p7zip-full bzip2 xz-utils wget curl \
                    qemu-user-static binfmt-support \
                    parted kpartx dosfstools \
                    coreutils util-linux
```

`qemu-user-static` + `binfmt-support` is what lets you `chroot` into an ARM64 root filesystem from an x86_64 PC.

### Flashing tool
- Linux: `dd` (built in)
- Cross-platform: **Raspberry Pi Imager** or **balenaEtcher**

> ⚠️ Always `umount` the SD card before `dd`, and triple-check `of=` — picking the wrong device wipes your laptop’s disk.

### The shared “magic” — ClockworkPi APT repo
Every recipe below pulls the uConsole CM4 kernel and utilities from this repo:

```
deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main
```

The package you must install is:

```
uconsole-kernel-cm4-rpi
```

Optional but useful packages:
- `uconsole-4g-util-cm4` — 4G modem helpers (only if you have the 4G expansion)

---

## 1. Raspberry Pi OS — the official method (pi-gen)

Since uConsole CM4 image **v2.0**, the official image is built with `pi-gen` on the `uconsole_arm64` branch. Latest as of January 2026 is **v2.1** with kernel **6.12.62-v8+**.

You have two paths: download the official image, or build it yourself with `pi-gen`.

### 1A. Just download the official image (quickest)

```bash
# Latest official CM4 image (v2.1, ~Jan 2026)
wget http://dl.clockworkpi.com/uConsole_CM4_v2.1_64bit.img.bz2

# Verify
md5sum uConsole_CM4_v2.1_64bit.img.bz2
# expected: b14715f3fe2789ef8b40dded37c3bc63

# Decompress
bunzip2 uConsole_CM4_v2.1_64bit.img.bz2
```

Then jump to **Section 4 — Flashing**. This gives you a working Raspberry Pi OS Bookworm with all uConsole tweaks already applied (LCD on at boot, brightness keys, rotated desktop, etc.).

### 1B. Build your own with pi-gen

This is what you want if you’re tweaking the base image, adding packages at build time, or producing your own customised distribution.

```bash
# 1. Clone Clockwork’s pi-gen fork
git clone -b uconsole_arm64 https://github.com/cuu/pi-gen.git
cd pi-gen

# 2. (Optional) Customise — edit config files in stage*/ to add/remove packages,
#    change hostname, default user, locale, etc.
#    Create a 'config' file in the pi-gen root if you want to override defaults:
cat > config <<'EOF'
IMG_NAME='uConsoleCustom'
TARGET_HOSTNAME='uconsole'
FIRST_USER_NAME='pi'
FIRST_USER_PASS='raspberry'
ENABLE_SSH=1
LOCALE_DEFAULT='en_US.UTF-8'
TIMEZONE_DEFAULT='UTC'
EOF

# 3. Build (must be Ubuntu, must be sudo, takes 30–90 min)
sudo ./build.sh
```

The finished `.img` ends up in `deploy/`. Skip to **Section 4 — Flashing**.

> Clockwork’s pi-gen fork includes their custom modifications: GPIO9 pulled high at boot (so the LCD turns on immediately), default backlight level 3, large-screen desktop scaling, black background, and `Fn+<>` brightness shortcuts.

### 1C. Build only the kernel (if you need it for another distro)

The uConsole kernel source is at `https://github.com/cuu/ClockworkPi-linux`. Cross-compile from x86_64 Ubuntu:

```bash
sudo apt install -y crossbuild-essential-arm64 bc bison flex libssl-dev make

git clone https://github.com/cuu/ClockworkPi-linux.git
cd ClockworkPi-linux

export KERNEL=kernel8
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

make bcm2711_defconfig
make -j$(nproc)

mkdir -p ../modules ../firmware/overlays
INSTALL_MOD_PATH=../modules make modules_install

cp arch/arm64/boot/Image                         ../firmware/$KERNEL.img
cp arch/arm64/boot/dts/broadcom/*.dtb            ../firmware
cp arch/arm64/boot/dts/overlays/*.dtb*           ../firmware/overlays/
cp arch/arm64/boot/dts/overlays/README           ../firmware/overlays/
```

You’d only do this if you want full control; for Kali/Parrot below, the prebuilt kernel from the APT repo is fine.

---

## 2. Kali Linux on uConsole CM4

**This is the official ClockworkPi recipe** (from their wiki, `Kali-linux-image-for-uConsole-cm4`). The principle: take Kali’s Raspberry Pi ARM64 image, remove the Kali Pi kernel, install ClockworkPi’s kernel, configure rotation, then flash. **Do everything below on a Linux build PC, not on the uConsole itself.**

### 2.1 Get the Kali Pi ARM64 image

Download the latest Kali Raspberry Pi ARM64 image from kali.org/get-kali (look for **Raspberry Pi → 64-bit**). The wiki recipe uses `kali-linux-2024.1-raspberry-pi-arm64.img.xz` but any newer release works the same way. Substitute the filename below.

```bash
# Example
wget https://kali.download/arm-images/kali-2025.x/kali-linux-2025.x-raspberry-pi-arm64.img.xz
xz -d kali-linux-2025.x-raspberry-pi-arm64.img.xz
# rename for the rest of the guide if you want
mv kali-linux-2025.x-raspberry-pi-arm64.img kali-uconsole.img
```

### 2.2 Grow the image (Kali is tight on space)

The default image fills the partition. Grow it ~4 GB before chrooting in, otherwise `apt install` will fail mid-step.

```bash
# Add 4 GB of zeros
dd if=/dev/zero bs=1M count=4096 >> kali-uconsole.img

# Grow the second partition to fill the new space
sudo parted kali-uconsole.img --script resizepart 2 100%
```

### 2.3 Loop-mount the image

```bash
sudo mkdir -p /mnt/p1

# Map partitions
LOOPDEV=$(sudo losetup -f --show -P kali-uconsole.img)
echo "Image is on $LOOPDEV"   # e.g. /dev/loop1

# Resize the filesystem to match the partition
sudo e2fsck -f ${LOOPDEV}p2
sudo resize2fs ${LOOPDEV}p2

# Mount root, then boot
sudo mount ${LOOPDEV}p2 /mnt/p1
sudo mount ${LOOPDEV}p1 /mnt/p1/boot
```

### 2.4 Prepare chroot

```bash
cd /mnt/p1
sudo mount --bind /dev      dev/
sudo mount --bind /sys      sys/
sudo mount --bind /proc     proc/
sudo mount --bind /dev/pts  dev/pts

# qemu so ARM64 binaries run under chroot on x86_64 host
sudo cp /usr/bin/qemu-aarch64-static usr/bin/ 2>/dev/null || true
```

### 2.5 Swap kernels and add ClockworkPi tweaks

```bash
# Remove Kali's Pi kernel + headers
sudo chroot /mnt/p1 /bin/bash -c 'apt remove -y kalipi-kernel kalipi-kernel-headers'

# Add the ClockworkPi APT repo
sudo chroot /mnt/p1 /bin/bash -c \
  'wget -q -O- https://raw.githubusercontent.com/clockworkpi/apt/main/debian/KEY.gpg \
   | gpg --dearmor | tee /etc/apt/trusted.gpg.d/clockworkpi.gpg > /dev/null'

sudo chroot /mnt/p1 /bin/bash -c \
  'echo "deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main" \
   > /etc/apt/sources.list.d/clockworkpi.list'

sudo chroot /mnt/p1 /bin/bash -c 'apt update'

# Install the uConsole CM4 kernel
sudo chroot /mnt/p1 /bin/bash -c 'apt install -y uconsole-kernel-cm4-rpi'

# Pin the Kali kernel packages to never reinstall (critical!)
sudo tee /mnt/p1/etc/apt/preferences.d/kalipi-kernel > /dev/null <<'EOF'
Package: kalipi-kernel
Pin: release *
Pin-Priority: -1
EOF

sudo tee /mnt/p1/etc/apt/preferences.d/kalipi-kernel-headers > /dev/null <<'EOF'
Package: kalipi-kernel-headers
Pin: release *
Pin-Priority: -1
EOF
```

### 2.6 Rotate the screen for LightDM

The uConsole LCD is mounted sideways relative to the Pi, so you need to rotate at the display-manager level.

```bash
sudo tee /mnt/p1/etc/lightdm/setup.sh > /dev/null <<'EOF'
#!/bin/bash
xrandr --output DSI-1 --rotate right
exit 0
EOF

sudo chmod +x /mnt/p1/etc/lightdm/setup.sh

sudo sed -i 's|^#greeter-setup-script=.*|greeter-setup-script=/etc/lightdm/setup.sh|' \
  /mnt/p1/etc/lightdm/lightdm.conf
```

For the user’s X session, also create `~/.xprofile` (or use the Xfce/`xrandr` autostart) with the same `xrandr --output DSI-1 --rotate right` line. The default Kali user is `kali`, password `kali`.

### 2.7 (Optional) 4G expansion module support

Skip this section if you don’t have the 4G card.

```bash
sudo chroot /mnt/p1 /bin/bash -c 'apt install -y pppoe uconsole-4g-util-cm4'

sudo tee /mnt/p1/etc/modprobe.d/blacklist-qmi.conf > /dev/null <<'EOF'
blacklist qmi_wwan
blacklist cdc_wdm
EOF
```

### 2.8 Clean up and unmount

```bash
sudo umount /mnt/p1/dev/pts
sudo umount /mnt/p1/dev
sudo umount /mnt/p1/proc
sudo umount /mnt/p1/sys

sudo rm -f /mnt/p1/root/.bash_history /mnt/p1/usr/bin/qemu-aarch64-static

sudo umount /mnt/p1/boot
sudo umount /mnt/p1
sudo losetup -D
```

Now jump to **Section 4 — Flashing**.

---

## 3. Parrot OS on uConsole CM4

**There is no official ClockworkPi recipe for Parrot.** Parrot’s Raspberry Pi images are based on Debian, just like Kali, and Parrot does publish a Pi ARM64 image (Core / Home / Security editions, tested on Pi 3B/4B/400/5). The same chroot-and-swap-kernel strategy works — you’re just doing what Kali’s recipe does, but to Parrot.

> ⚠️ This works for me but is not vendor-blessed. The kernel module ABI and userspace expectations can shift between Parrot releases. If something breaks, the trick is almost always: a leftover Parrot kernel package competing with `uconsole-kernel-cm4-rpi`. Try this on a 32 GB SD first; don’t commit it to your only working SD card.

### 3.1 Download the Parrot Pi ARM64 image

From `parrotsec.org` → Downloads → Raspberry Pi. Pick **Home** (lighter) or **Security** (full pentest toolset). Files are `.img.xz`.

```bash
# Replace VERSION with the current Parrot release
wget https://download.parrot.sh/parrot/iso/VERSION/Parrot-rpi-VERSION_arm64.img.xz
xz -d Parrot-rpi-VERSION_arm64.img.xz
mv Parrot-rpi-VERSION_arm64.img parrot-uconsole.img
```

### 3.2 Grow + loop-mount

Same as Kali — Parrot Security especially is tight:

```bash
dd if=/dev/zero bs=1M count=4096 >> parrot-uconsole.img
sudo parted parrot-uconsole.img --script resizepart 2 100%

sudo mkdir -p /mnt/p1
LOOPDEV=$(sudo losetup -f --show -P parrot-uconsole.img)

sudo e2fsck -f ${LOOPDEV}p2
sudo resize2fs ${LOOPDEV}p2

sudo mount ${LOOPDEV}p2 /mnt/p1
sudo mount ${LOOPDEV}p1 /mnt/p1/boot

cd /mnt/p1
sudo mount --bind /dev      dev/
sudo mount --bind /sys      sys/
sudo mount --bind /proc     proc/
sudo mount --bind /dev/pts  dev/pts
sudo cp /usr/bin/qemu-aarch64-static usr/bin/
```

### 3.3 Identify and remove Parrot’s Pi kernel

Find what kernel package Parrot ships (it usually depends on the release — could be `linux-image-*-arm64`, `raspi-firmware`, or a Parrot-specific kernel):

```bash
sudo chroot /mnt/p1 /bin/bash -c 'dpkg -l | grep -E "linux-image|raspi|kernel"'
```

Note the package names, then remove them:

```bash
# Replace with the actual package(s) from the previous step
sudo chroot /mnt/p1 /bin/bash -c 'apt remove -y linux-image-arm64 raspi-firmware'
```

### 3.4 Add ClockworkPi repo and install the uConsole kernel

Identical to Kali:

```bash
sudo chroot /mnt/p1 /bin/bash -c \
  'wget -q -O- https://raw.githubusercontent.com/clockworkpi/apt/main/debian/KEY.gpg \
   | gpg --dearmor | tee /etc/apt/trusted.gpg.d/clockworkpi.gpg > /dev/null'

sudo chroot /mnt/p1 /bin/bash -c \
  'echo "deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main" \
   > /etc/apt/sources.list.d/clockworkpi.list'

sudo chroot /mnt/p1 /bin/bash -c 'apt update && apt install -y uconsole-kernel-cm4-rpi'
```

Pin the original Parrot kernel(s) so future `apt upgrade` doesn’t bring them back:

```bash
sudo tee /mnt/p1/etc/apt/preferences.d/parrot-kernel-pin > /dev/null <<'EOF'
Package: linux-image-arm64
Pin: release *
Pin-Priority: -1

Package: raspi-firmware
Pin: release *
Pin-Priority: -1
EOF
```

### 3.5 Display rotation

Parrot uses LightDM as well (or sometimes GDM3 for the MATE edition). For LightDM, use the same recipe as Kali in 2.6.

For MATE/GDM3, instead set rotation via a per-user autostart entry:

```bash
sudo mkdir -p /mnt/p1/etc/skel/.config/autostart
sudo tee /mnt/p1/etc/skel/.config/autostart/uconsole-rotate.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=uConsole rotate
Exec=sh -c "xrandr --output DSI-1 --rotate right"
X-GNOME-Autostart-enabled=true
EOF
```

(The default Parrot user is `parrot` / password `parrot`.)

### 3.6 (Optional) 4G

Same as Kali 2.7. Replace `pppoe` with whatever Parrot ships if there’s a conflict:

```bash
sudo chroot /mnt/p1 /bin/bash -c 'apt install -y pppoe uconsole-4g-util-cm4'

sudo tee /mnt/p1/etc/modprobe.d/blacklist-qmi.conf > /dev/null <<'EOF'
blacklist qmi_wwan
blacklist cdc_wdm
EOF
```

### 3.7 Unmount

```bash
sudo umount /mnt/p1/dev/pts /mnt/p1/dev /mnt/p1/proc /mnt/p1/sys
sudo rm -f /mnt/p1/usr/bin/qemu-aarch64-static
sudo umount /mnt/p1/boot
sudo umount /mnt/p1
sudo losetup -D
```

---

## 4. Flashing the image to microSD

### Linux (`dd`)

```bash
# Find the SD card device
lsblk
# e.g. /dev/sdX or /dev/mmcblk0 — DO NOT pick your laptop’s disk!

# Unmount any auto-mounted partitions
sudo umount /dev/sdX*  2>/dev/null

# Write
sudo dd if=uConsole_CM4_v2.1_64bit.img of=/dev/sdX bs=8M status=progress conv=fsync
sync
```

For `mmcblk0`, the device is `/dev/mmcblk0` (whole card) — not `/dev/mmcblk0p1`.

### Windows / macOS

Use **Raspberry Pi Imager** (`Choose OS → Use custom`) or **balenaEtcher**. Point it at the `.img` you produced and the SD card. Let it verify after writing.

> If using Raspberry Pi Imager on a custom uConsole image, **disable** the “OS customisation” feature — its auto-config will overwrite ClockworkPi-specific settings on first boot.

---

## 5. First boot

1. Insert the microSD into the uConsole.
2. Plug in USB-C power **and** install at least one charged 18650 cell — the uConsole will not power on from USB-C alone if no batteries are installed (PMU expects a battery to regulate from).
3. Hold the power switch for ~2 seconds. The screen should light up immediately (that’s the GPIO9 pull-up at work).
4. Default credentials:
   - **Raspberry Pi OS** (official build): `cpi` / `cpi`
   - **Raspberry Pi OS** (your pi-gen build): whatever you set in `config`
   - **Kali**: `kali` / `kali`
   - **Parrot**: `parrot` / `parrot`
5. First action: change the password, run `sudo apt update && sudo apt full-upgrade`, and expand the filesystem if needed (`sudo raspi-config` → Advanced → Expand Filesystem on Pi OS; on Kali/Parrot, GParted or `growpart` + `resize2fs`).

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Black screen forever | Wrong kernel installed (Kali/Parrot kernel still active) | Rebuild image, make sure `uconsole-kernel-cm4-rpi` was installed *after* removing the original kernel; check `/boot/config.txt` references `kernel8.img` |
| Display rotated 90° on Pi OS | You used a community image without rotation tweaks | `xrandr --output DSI-1 --rotate right`, or rebuild with the official pi-gen recipe |
| Backlight keys do nothing | You skipped pi-gen and didn’t install `uconsole-kernel-cm4-rpi` | Install the kernel package; the `Fn+<>` mapping needs the ClockworkPi kernel + DTBs |
| 4G modem not detected | `qmi_wwan` / `cdc_wdm` not blacklisted | Confirm `/etc/modprobe.d/blacklist-qmi.conf` exists and contains both lines, then reboot |
| `apt full-upgrade` reinstalls original kernel and bricks display | Pin file missing | Recreate the `apt preferences.d` pin (Section 2.5 / 3.4) and reinstall `uconsole-kernel-cm4-rpi` |
| `chroot: failed to run command '/bin/bash': Exec format error` | Missing qemu-user-static | `sudo apt install qemu-user-static binfmt-support` and copy `qemu-aarch64-static` into the image’s `usr/bin/` |
| Won’t boot from USB-C charger alone | No 18650 cells installed | Install at least one cell; the PMU needs a battery to regulate |

---

## 7. Useful references

- ClockworkPi uConsole repo: `https://github.com/clockworkpi/uConsole`
- Official image releases: `https://github.com/clockworkpi/uConsole/tree/master/images`
- Image-build wiki: `https://github.com/clockworkpi/uConsole/wiki/How-uConsole-CM4-os-image-made`
- Kali recipe wiki: `https://github.com/clockworkpi/uConsole/wiki/Kali-linux-image-for-uConsole-cm4`
- Clockwork pi-gen fork: `https://github.com/cuu/pi-gen/tree/uconsole_arm64`
- Clockwork kernel source: `https://github.com/cuu/ClockworkPi-linux`
- ClockworkPi APT repo: `https://github.com/clockworkpi/apt`
- Parrot Pi install docs: `https://parrotsec.org/docs/installation/raspberrypi/`
- Community OS forum thread: `https://forum.clockworkpi.com/t/uconsole-os-images/10432`
- Community “Bookworm 6.6.y for the uConsole and DevTerm” thread: `https://forum.clockworkpi.com/t/bookworm-6-6-y-for-the-uconsole-and-devterm/13235`

Happy hacking.
