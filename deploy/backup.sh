#!/bin/bash
# backup.sh — Pull current state from the Rock 5B for safekeeping.
#
# Usage: ./deploy/backup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$PROJECT_DIR/.env"

SSH_OPTS="-o StrictHostKeyChecking=no"
if [ -f "$PROJECT_DIR/$ROCK_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $PROJECT_DIR/$ROCK_KEY"
fi

BACKUP_DIR="$PROJECT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "=== CarStereo Backup ==="
echo "Saving to: $BACKUP_DIR"
echo ""

# Boot configuration
echo "Pulling boot config..."
mkdir -p "$BACKUP_DIR/boot"
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:/boot/armbianEnv.txt" "$BACKUP_DIR/boot/"
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:/boot/armbianEnv.txt.bak" "$BACKUP_DIR/boot/" 2>/dev/null || true
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "ls -la /boot/Image /boot/uInitrd /boot/dtb /boot/vmlinuz" > "$BACKUP_DIR/boot/symlinks.txt"

# Home scripts
echo "Pulling home scripts..."
mkdir -p "$BACKUP_DIR/home"
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:~/start-dash.sh" "$BACKUP_DIR/home/" 2>/dev/null || true
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:~/waydroid_gps_reflector.py" "$BACKUP_DIR/home/" 2>/dev/null || true
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:~/drm-dpms-daemon.py" "$BACKUP_DIR/home/" 2>/dev/null || true
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:~/usb-park.sh" "$BACKUP_DIR/home/" 2>/dev/null || true

# Systemd services
echo "Pulling systemd services..."
mkdir -p "$BACKUP_DIR/systemd"
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "ls /etc/systemd/system/*.service /etc/systemd/system/*.timer 2>/dev/null | grep -v systemd | grep -v snap" | while read svc; do
    scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:$svc" "$BACKUP_DIR/systemd/" 2>/dev/null || true
done

# Waydroid config
echo "Pulling waydroid config..."
mkdir -p "$BACKUP_DIR/waydroid"
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:/var/lib/waydroid/waydroid.cfg" "$BACKUP_DIR/waydroid/" 2>/dev/null || true
scp $SSH_OPTS "$ROCK_USER@$ROCK_HOST:/var/lib/waydroid/waydroid_base.prop" "$BACKUP_DIR/waydroid/" 2>/dev/null || true

# Package state
echo "Pulling package state..."
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "apt-mark showhold" > "$BACKUP_DIR/apt-hold.txt"
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "dpkg -l | grep -iE 'linux-image|linux-u-boot|armbian|waydroid|gpsd|cage|pipewire'" > "$BACKUP_DIR/packages.txt"

# System info
echo "Pulling system info..."
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "uname -a" > "$BACKUP_DIR/uname.txt"
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "lsblk" > "$BACKUP_DIR/lsblk.txt"
ssh $SSH_OPTS "$ROCK_USER@$ROCK_HOST" "lsusb" > "$BACKUP_DIR/lsusb.txt"

echo ""
echo "=== Backup complete: $BACKUP_DIR ==="
ls -la "$BACKUP_DIR"
