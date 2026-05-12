#!/bin/bash
# boot-fix.sh — Fix mismatched uInitrd/DTB symlinks after a broken kernel upgrade.
#
# Run this either:
#   - From the running system (if it somehow booted)
#   - From a chroot after booting from SD card:
#       mount /dev/nvme0n1p1 /mnt
#       mount --bind /dev /mnt/dev && mount --bind /proc /mnt/proc && mount --bind /sys /mnt/sys
#       chroot /mnt /opt/carstereo/deploy/boot-fix.sh
#
# What it does:
#   1. Finds the newest installed kernel version
#   2. Checks if uInitrd and dtb symlinks match
#   3. Creates uInitrd from initrd.img if missing
#   4. Copies DTBs from /usr/lib/linux-image-* if missing
#   5. Updates symlinks

set -e

BOOT="/boot"

echo "=== CarStereo Boot Fix ==="

# Find newest kernel version
NEWEST_KERNEL=$(ls -1 ${BOOT}/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|.*/vmlinuz-||')
if [ -z "$NEWEST_KERNEL" ]; then
    echo "ERROR: No kernel found in ${BOOT}/"
    exit 1
fi
echo "Newest kernel: $NEWEST_KERNEL"

# Check current symlink state
echo ""
echo "Current symlinks:"
ls -la ${BOOT}/Image ${BOOT}/uInitrd ${BOOT}/dtb 2>/dev/null || true

# --- Fix Image symlink ---
if [ "$(readlink ${BOOT}/Image)" != "vmlinuz-${NEWEST_KERNEL}" ]; then
    echo ""
    echo "Fixing Image symlink..."
    ln -sf "vmlinuz-${NEWEST_KERNEL}" "${BOOT}/Image"
    ln -sf "vmlinuz-${NEWEST_KERNEL}" "${BOOT}/vmlinuz"
fi

# --- Fix uInitrd ---
UINITRD_TARGET="uInitrd-${NEWEST_KERNEL}"
if [ ! -f "${BOOT}/${UINITRD_TARGET}" ]; then
    INITRD="${BOOT}/initrd.img-${NEWEST_KERNEL}"
    if [ ! -f "$INITRD" ]; then
        echo "ERROR: No initrd.img for ${NEWEST_KERNEL}. Run: update-initramfs -c -k ${NEWEST_KERNEL}"
        exit 1
    fi
    echo ""
    echo "Creating ${UINITRD_TARGET} from initrd.img..."
    mkimage -A arm64 -T ramdisk -C none -n "uInitrd" -d "$INITRD" "${BOOT}/${UINITRD_TARGET}"
fi

if [ "$(readlink ${BOOT}/uInitrd)" != "${UINITRD_TARGET}" ]; then
    echo "Fixing uInitrd symlink..."
    ln -sf "${UINITRD_TARGET}" "${BOOT}/uInitrd"
fi

# --- Fix DTB ---
DTB_DIR="dtb-${NEWEST_KERNEL}"
if [ ! -d "${BOOT}/${DTB_DIR}" ]; then
    SRC="/usr/lib/linux-image-${NEWEST_KERNEL}"
    if [ -d "$SRC" ]; then
        echo ""
        echo "Copying DTBs from ${SRC}..."
        cp -a "$SRC" "${BOOT}/${DTB_DIR}"
    else
        echo "WARNING: No DTB source at ${SRC}. Using existing dtb directory."
    fi
fi

if [ -d "${BOOT}/${DTB_DIR}" ] && [ "$(readlink ${BOOT}/dtb)" != "${DTB_DIR}" ]; then
    echo "Fixing dtb symlink..."
    ln -sf "${DTB_DIR}" "${BOOT}/dtb"
fi

sync

echo ""
echo "=== Fixed symlinks ==="
ls -la ${BOOT}/Image ${BOOT}/uInitrd ${BOOT}/dtb
echo ""
echo "Boot fix complete. Safe to reboot."
