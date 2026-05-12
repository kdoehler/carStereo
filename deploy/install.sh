#!/bin/bash
# install.sh — On-device installer for CarStereo services.
# This runs ON the Rock 5B (pushed by deploy.sh).
#
# Usage:
#   sudo ./install.sh          # install everything
#   sudo ./install.sh gps      # install single service

set -e

INSTALL_DIR="/opt/carstereo"
SERVICE_TARGET=""

if [ "$1" ]; then
    SERVICE_TARGET="$1"
fi

echo "=== CarStereo Install ==="

# --- Install systemd services ---
install_service() {
    local svc_dir="$1"
    local svc_name=$(basename "$svc_dir")

    for unit_file in "$svc_dir"/*.service "$svc_dir"/*.timer; do
        [ -f "$unit_file" ] || continue
        local unit_name=$(basename "$unit_file")
        echo "Installing $unit_name..."
        cp "$unit_file" "/etc/systemd/system/$unit_name"
    done
}

if [ -n "$SERVICE_TARGET" ]; then
    if [ -d "$INSTALL_DIR/services/$SERVICE_TARGET" ]; then
        install_service "$INSTALL_DIR/services/$SERVICE_TARGET"
    else
        echo "ERROR: Service $SERVICE_TARGET not found"
        exit 1
    fi
else
    # Install all services
    for svc_dir in "$INSTALL_DIR/services"/*/; do
        [ -d "$svc_dir" ] && install_service "$svc_dir"
    done

    # Copy launcher to home
    if [ -f "$INSTALL_DIR/services/launcher/start-dash.sh" ]; then
        cp "$INSTALL_DIR/services/launcher/start-dash.sh" "/home/ganimed/start-dash.sh"
        chown ganimed:ganimed "/home/ganimed/start-dash.sh"
        chmod +x "/home/ganimed/start-dash.sh"
    fi

    # Copy GPS reflector to home (referenced by start-dash.sh)
    if [ -f "$INSTALL_DIR/services/gps/waydroid_gps_reflector.py" ]; then
        cp "$INSTALL_DIR/services/gps/waydroid_gps_reflector.py" "/home/ganimed/waydroid_gps_reflector.py"
        chown ganimed:ganimed "/home/ganimed/waydroid_gps_reflector.py"
    fi

    # Copy boot-fix to /usr/local/bin
    if [ -f "$INSTALL_DIR/deploy/boot-fix.sh" ]; then
        cp "$INSTALL_DIR/deploy/boot-fix.sh" "/usr/local/bin/carstereo-boot-fix"
        chmod +x "/usr/local/bin/carstereo-boot-fix"
    fi
fi

# Reload systemd
systemctl daemon-reload

echo ""
echo "=== Install complete ==="
echo "Installed services:"
ls /etc/systemd/system/carstereo-* /etc/systemd/system/waydroid-gps*.service /etc/systemd/system/gps-bridge.service 2>/dev/null || echo "  (no services installed yet)"
