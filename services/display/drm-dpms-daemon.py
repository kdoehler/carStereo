#!/usr/bin/env python3
"""
drm-dpms-daemon.py - Hold HDMI DPMS Off by keeping DRM master open.

Usage:
  sudo python3 drm-dpms-daemon.py off   # display off, runs until killed
  sudo python3 drm-dpms-daemon.py on    # one-shot restore display

Signals:
  SIGTERM / SIGINT: restore display and exit
"""

import os, fcntl, struct, signal, time, sys

# --- DRM ioctl numbers (arm64 Linux) ---
# _IO('d', 0x1e) = SET_MASTER
DRM_IOCTL_SET_MASTER       = 0x641e
# _IO('d', 0x1f) = DROP_MASTER
DRM_IOCTL_DROP_MASTER      = 0x641f
# _IOWR('d', 0xba, 24) = MODE_OBJ_SETPROPERTY
DRM_IOCTL_MODE_OBJ_SETPROPERTY = 0xc01864ba

DRM_MODE_OBJECT_CONNECTOR  = 0xc0c0c0c0

DEVICE       = '/dev/dri/card0'
CONNECTOR_ID = 84
DPMS_PROP_ID = 2   # from: modetest -M rockchip -c | grep DPMS

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
