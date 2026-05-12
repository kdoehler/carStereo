#!/bin/bash
# Pin dangerous packages to prevent accidental boot breakage.
# Run this ONCE on the Rock 5B after any fresh install or kernel update.
#
# Background: On May 11, 2026 an `apt upgrade` updated the kernel from
# 6.18.8 to 6.18.10 but failed to create the uInitrd (mkimage-wrapped
# initramfs) and failed to install DTBs for the new version, resulting
# in an unbootable system that required SD card rescue.

set -e

echo "=== Pinning dangerous packages ==="

sudo apt-mark hold linux-u-boot-rock-5b-current
sudo apt-mark hold linux-image-current-rockchip64
sudo apt-mark hold armbian-firmware

echo ""
echo "=== Currently held packages ==="
apt-mark showhold

echo ""
echo "Done. These packages will NOT be upgraded by apt upgrade."
echo "To intentionally upgrade, run: sudo apt-mark unhold <package>"
