#!/usr/bin/env python3
"""
drm-dpms-daemon.py - Hold HDMI DPMS Off by keeping DRM master open.

Usage:
  sudo python3 drm-dpms-daemon.py off   # display off, runs until killed
  sudo python3 drm-dpms-daemon.py on    # one-shot restore display

Signals:
  SIGTERM / SIGINT: restore display and exit
"""

import os, fcntl, struct, signal, time, sys, glob

# --- DRM ioctl numbers (arm64 Linux) ---
# _IO('d', 0x1e) = SET_MASTER
DRM_IOCTL_SET_MASTER       = 0x641e
# _IO('d', 0x1f) = DROP_MASTER
DRM_IOCTL_DROP_MASTER      = 0x641f
# _IOWR('d', 0xba, 24) = MODE_OBJ_SETPROPERTY
DRM_IOCTL_MODE_OBJ_SETPROPERTY = 0xc01864ba
# _IOWR('d', 0xa1, 32) = MODE_GETCONNECTOR (for connector_id discovery)
DRM_IOCTL_MODE_GETRESOURCES = 0xc04064a0

DRM_MODE_OBJECT_CONNECTOR  = 0xc0c0c0c0

DPMS_PROP_ID = 2   # Standard DPMS property ID


def find_drm_card_and_connector():
    """Auto-detect the DRM card device and HDMI connector ID.

    Scans /sys/class/drm/ for connected HDMI connectors and resolves
    the corresponding /dev/dri/cardN device and connector_id.
    """
    # Find connected HDMI connector in sysfs
    for path in sorted(glob.glob('/sys/class/drm/card*-HDMI-*')):
        try:
            with open(os.path.join(path, 'status')) as f:
                if f.read().strip() != 'connected':
                    continue
        except (OSError, IOError):
            continue

        # Extract card number from e.g. "card2-HDMI-A-3"
        dirname = os.path.basename(path)
        card_num = dirname.split('-')[0]  # "card2"
        device = f'/dev/dri/{card_num}'

        # Read connector_id from sysfs (available on modern kernels)
        connector_id = None
        try:
            with open(os.path.join(path, 'connector_id')) as f:
                connector_id = int(f.read().strip())
        except (OSError, IOError, ValueError):
            pass

        if connector_id and os.path.exists(device):
            print(f'Auto-detected: {device}, connector {connector_id} ({dirname})', flush=True)
            return device, connector_id

    # Fallback to card0 connector 84 (original defaults)
    print('WARNING: Could not auto-detect HDMI connector, using defaults', flush=True)
    return '/dev/dri/card0', 84


DEVICE, CONNECTOR_ID = find_drm_card_and_connector()

DPMS_ON  = 0
DPMS_OFF = 3

running = True

def set_dpms(fd, value):
    # struct drm_mode_obj_set_property { u64 value; u32 prop_id; u32 obj_id; u32 obj_type; u32 pad; }
    data = struct.pack('=QIIII', value, DPMS_PROP_ID, CONNECTOR_ID, DRM_MODE_OBJECT_CONNECTOR, 0)
    fcntl.ioctl(fd, DRM_IOCTL_MODE_OBJ_SETPROPERTY, bytearray(data))
    print(f'DPMS set to {value} ({"OFF" if value == DPMS_OFF else "ON"})', flush=True)

def on_signal(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

if len(sys.argv) < 2 or sys.argv[1] not in ('on', 'off'):
    print(f'Usage: {sys.argv[0]} [on|off]')
    sys.exit(1)

fd = os.open(DEVICE, os.O_RDWR)
try:
    try:
        fcntl.ioctl(fd, DRM_IOCTL_SET_MASTER, 0)
        print('DRM master acquired', flush=True)
    except OSError as e:
        print(f'SET_MASTER failed ({e}) - continuing without master', flush=True)

    if sys.argv[1] == 'on':
        set_dpms(fd, DPMS_ON)
    else:
        set_dpms(fd, DPMS_OFF)
        print('Holding display off. Send SIGTERM to restore.', flush=True)
        while running:
            time.sleep(1)
        print('Restoring display...', flush=True)
        set_dpms(fd, DPMS_ON)

finally:
    try:
        fcntl.ioctl(fd, DRM_IOCTL_DROP_MASTER, 0)
    except OSError:
        pass
    os.close(fd)
    print('Done.', flush=True)
