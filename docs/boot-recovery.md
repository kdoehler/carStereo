# Boot Recovery Guide

## The May 2026 Incident

On May 11, 2026, an `apt upgrade` updated `linux-image-current-rockchip64` from 6.18.8 to 6.18.10 (same Armbian version 26.2.1). The package:

- ✅ Updated `Image` and `vmlinuz` symlinks → 6.18.10
- ✅ Created `initrd.img-6.18.10-current-rockchip64`
- ❌ **Failed to create** `uInitrd-6.18.10-current-rockchip64` (mkimage-wrapped initramfs)
- ❌ **Failed to install** `dtb-6.18.10-current-rockchip64` to `/boot/`
- ❌ **Left** `uInitrd` symlink pointing to old 6.18.8 version
- ❌ **Left** `dtb` symlink pointing to old 6.18.8 directory

**Result**: U-Boot loaded the 6.18.10 kernel with 6.18.8 initramfs (wrong modules) → NVMe driver never loaded → root filesystem not found → unbootable.

The `linux-u-boot-rock-5b-current` package was also "upgraded" (same version) but its postinst only flashes SPI when `FORCE_UBOOT_UPDATE=yes` (default: no), so SPI bootloader was untouched.

## Prevention

```bash
# Pin these packages permanently
sudo apt-mark hold linux-u-boot-rock-5b-current
sudo apt-mark hold linux-image-current-rockchip64
sudo apt-mark hold armbian-firmware

# Or use: make apt-hold
```

## Recovery Procedure

### 1. Boot from SD card
Insert the Armbian SD card (the one used for initial install works fine) and power on. The Rock 5B boots from SD when SPI U-Boot can't find NVMe root.

### 2. Mount NVMe
```bash
sudo mount /dev/nvme0n1p1 /mnt
```

### 3. Diagnose
```bash
# Check what kernel is installed
ls -la /mnt/boot/Image /mnt/boot/vmlinuz

# Check if symlinks match
ls -la /mnt/boot/uInitrd /mnt/boot/dtb

# The kernel version from Image should match uInitrd and dtb
```

### 4. Fix (automated)
```bash
# If boot-fix.sh is on the NVMe:
sudo chroot /mnt /opt/carstereo/deploy/boot-fix.sh

# Or run manually from this repo:
sudo bash deploy/boot-fix.sh  # (after adjusting BOOT= to /mnt/boot)
```

### 5. Fix (manual)
```bash
# Create uInitrd from initrd.img
KVER="6.18.10-current-rockchip64"  # adjust to actual version

sudo mkimage -A arm64 -T ramdisk -C none -n "uInitrd" \
  -d /mnt/boot/initrd.img-${KVER} \
  /mnt/boot/uInitrd-${KVER}

sudo ln -sf uInitrd-${KVER} /mnt/boot/uInitrd

# Copy DTBs if missing
sudo cp -a /mnt/usr/lib/linux-image-${KVER} /mnt/boot/dtb-${KVER}
sudo ln -sf dtb-${KVER} /mnt/boot/dtb

sync
```

### 6. Reboot
Power off, remove SD card, power on. Should boot from NVMe.

## Boot Chain

```
SPI NOR Flash (U-Boot)
  → reads /boot/boot.scr (compiled from boot.cmd)
  → loads /boot/armbianEnv.txt (rootdev=UUID=...)
  → loads /boot/Image (kernel)
  → loads /boot/uInitrd (initramfs, mkimage-wrapped)
  → loads /boot/dtb/<fdtfile> (device tree)
  → boots kernel with root=UUID=...
  → initramfs loads NVMe driver → mounts root → systemd
```

## Key Files

| File | Purpose |
|---|---|
| `/boot/armbianEnv.txt` | Boot parameters (rootdev, overlays, extraargs) |
| `/boot/boot.scr` | Compiled U-Boot script (DO NOT EDIT — edit boot.cmd) |
| `/boot/boot.cmd` | U-Boot script source |
| `/boot/Image` | Symlink → current kernel |
| `/boot/uInitrd` | Symlink → mkimage-wrapped initramfs |
| `/boot/dtb` | Symlink → DTB directory for current kernel |
