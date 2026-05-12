# GPS Integration — Evolution

> **TL;DR**: Getting GPS data from a USB dongle into Android (Waydroid) required 4 iterations. The final solution uses `gpsd` → Python reflector → Appium Settings mock location injection.

---

## The Problem

Waydroid (Android in an LXC container) doesn't have direct access to host USB serial devices. Android apps like Google Maps, Waze, and OBD apps need GPS data, but the USB GPS dongle (`/dev/ttyUSB0`) is only visible to the Linux host.

## Version 1: Direct Serial Passthrough (`start-dash.sh.bak`)

**Approach**: Create a character device node directly inside the Waydroid container.

```bash
# Configure the serial port on the host
sudo stty -F /dev/ttyUSB0 38400 raw -echo

# Wait for Android boot, then create the device node inside the container
sudo waydroid shell "mknod /dev/ttyUSB0 c 188 0 && chmod 666 /dev/ttyUSB0"
```

**Result**: ❌ The device node gets created but Android can't read from it. The LXC container's `/dev` is a separate tmpfs — creating a node doesn't bridge the actual device through the namespace boundary. SELinux also blocks access.

### Source: [`archive/start-dash.sh.bak`](../archive/start-dash.sh.bak)

## Version 2: LXC PID + mknod (`start-dash.sh.bak2`)

**Approach**: Instead of running `waydroid shell`, find the container's PID from the host using `lxc-info` and create the device node directly in the container's `/proc/<pid>/root/dev` filesystem.

```bash
# Get the Waydroid container PID from the host
PID=$(sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid -p -H)

# Create the device node via the host's /proc view
ANDROID_DEV="/proc/$PID/root/dev"
sudo mknod $ANDROID_DEV/ttyUSB0 c 188 0
sudo chmod 666 $ANDROID_DEV/ttyUSB0

# Disable SELinux enforcement
sudo waydroid shell setenforce 0
```

**Result**: ⚠️ Better — the device node appears inside Android and some apps could see it. But the container's cgroup device whitelist blocks actual read/write access to major:minor 188:0. Also required `setenforce 0` which is a security concern.

### Source: [`archive/start-dash.sh.bak2`](../archive/start-dash.sh.bak2)

## Version 3: nsenter + bind mount (`start-dash.sh.save`)

**Approach**: Use `nsenter` to enter the container's mount namespace and bind-mount the real device.

```bash
CONTAINER_PID=$(sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid -p -H)

# Enter the container's namespace and bind-mount the device
sudo nsenter -t $CONTAINER_PID -m -u -i -n -p touch /dev/ttyUSB0
sudo nsenter -t $CONTAINER_PID -m -u -i -n -p mount --bind /dev/ttyUSB0 /dev/ttyUSB0
sudo nsenter -t $CONTAINER_PID -m -u -i -n -p chmod 666 /dev/ttyUSB0
```

**Result**: ❌ The bind mount either fails (different mount namespace for `/dev`) or succeeds but still hits the cgroup device whitelist. Even with SELinux permissive, Android's HAL doesn't know how to talk to a raw serial GPS.

### Source: [`archive/start-dash.sh.save`](../archive/start-dash.sh.save)

## Interlude: systemd Service Approaches

While iterating on the serial passthrough, two systemd services were created for bridging GPS data:

### `gps-bridge.service` — Raw socat bridge (v1)
```ini
ExecStart=/usr/bin/socat -d -d /dev/ttyUSB0,raw,echo=0 TCP-LISTEN:2947,reuseaddr,fork
```
Exposed the raw serial GPS as a TCP socket. Android apps couldn't use it because they expect the Android Location API, not a TCP NMEA stream.

### `waydroid-gps-bridge.service` — gpspipe + socat (v2)
```ini
ExecStart=/bin/sh -c "/usr/bin/gpspipe -r | /usr/bin/socat - TCP-LISTEN:2948,reuseaddr,fork"
```
Used `gpsd` to parse the GPS data and `gpspipe` to output clean NMEA. Several variations were tried:
- PTY link at `/dev/bus/gps/tty0`
- TCP bridge on port 2948
- Filtered to `$GP` sentences only

Still didn't solve the fundamental problem: Android apps use the Location API, not raw NMEA.

### Sources: [`services/gps/gps-bridge.service`](../services/gps/gps-bridge.service), [`services/gps/waydroid-gps-bridge.service`](../services/gps/waydroid-gps-bridge.service)

## Version 4: gpsd + Python Reflector + Appium Settings ✅ (Current)

**The insight**: Stop trying to pass the serial device into Android. Instead, use `gpsd` on the host to parse GPS data, then inject it into Android's Location API via the [Appium Settings](https://github.com/nicknsy/waydroid_script) app's mock location service.

### Architecture
```
USB GPS dongle (/dev/ttyUSB0)
  → gpsd (parses NMEA)
    → gpspipe -w (JSON output)
      → waydroid_gps_reflector.py (Python)
        → waydroid shell am start-foreground-service (Appium Settings)
          → Android Location API (mock location)
            → Google Maps, Waze, etc.
```

### How the reflector works:
```python
# Read JSON from gpspipe
data = json.loads(line)  # {"class":"TPV", "lat":48.1, "lon":11.5, ...}

# Inject via Appium Settings mock location service
cmd = (
    f'am start-foreground-service --user 0 '
    f'-n io.appium.settings/.LocationService '
    f'--es longitude "{lon}" --es latitude "{lat}" --es altitude "{alt}" '
    f'--es speed "{spd}" --es bearing "{brg}" --es bearingAccuracy "{brg_acc}"'
)
shell.stdin.write(cmd + '\n')
```

Key details:
- Uses a **persistent** `waydroid shell` subprocess (not one-shot per update)
- Reads `gpspipe -w` JSON stream (not raw NMEA)
- Extracts: latitude, longitude, altitude, speed, **bearing** (compass heading), bearing accuracy
- Updates at 1Hz (throttled via `time.time()` delta)
- Mock location permission granted via: `waydroid shell appops set de.pilablu.gpsconnector android:mock_location allow`

**Result**: ✅ Works perfectly. Google Maps shows accurate position with proper blue dot rotation (bearing). Navigation works. No SELinux issues, no namespace hacking.

### Prerequisites:
1. `gpsd` installed and running (`sudo apt install gpsd`)
2. `gpspipe` available (part of `gpsd-clients`)
3. Appium Settings APK installed in Waydroid (`settings_apk-debug.apk`)
4. Mock location permission granted for the Appium Settings app

### Sources: [`services/gps/waydroid_gps_reflector.py`](../services/gps/waydroid_gps_reflector.py), [`services/gps/waydroid-gps.service`](../services/gps/waydroid-gps.service)

---

## Summary

| Version | Approach | Outcome |
|---|---|---|
| v1 | `waydroid shell mknod` | ❌ Device node doesn't bridge namespaces |
| v2 | `/proc/<pid>/root/dev` mknod | ⚠️ Created but cgroup blocks access |
| v3 | `nsenter` bind mount | ❌ Mount namespace isolation |
| socat v1 | Raw serial → TCP:2947 | ❌ Apps need Location API, not NMEA |
| socat v2 | gpspipe → TCP:2948 | ❌ Same problem |
| **v4** | **gpsd → Python → Appium Settings** | **✅ Works perfectly** |

The key lesson: **don't fight container isolation** — use the Android API (mock location) as the integration point.
