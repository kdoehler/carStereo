# CarStereo 🚐

Camper van head unit built on a **Radxa Rock 5B** with a 10" touchscreen.

**Stack**: Armbian (Ubuntu) → Waydroid (Android/LineageOS) → Car Launcher

## Quick Start

```bash
# Deploy to device
cp .env.example .env   # edit with your credentials
make deploy

# SSH into device
make ssh

# Pull backup from device
make backup

# Emergency boot fix
make boot-fix
```

## Architecture

- **Host OS**: Armbian minimal (Ubuntu 24.04), kernel 6.18.x, NVMe boot via SPI
- **Android**: Waydroid 1.6.2 (LineageOS + GApps) in `cage` Wayland kiosk
- **GPS**: gpsd → Python reflector → Appium Settings mock location
- **Display**: DRM DPMS daemon for screen on/off control
- **USB Power**: EHCI/OHCI unbind + regulator kill for parked mode
- **Audio**: PipeWire → ALSA (HDMI + ES8316 onboard, I2S to JAB5 planned)

## Hardware

| Component | Interface | Status |
|---|---|---|
| Rock 5B | — | ✅ |
| 10" Touchscreen | HDMI + USB | ✅ |
| USB GPS Dongle | USB Serial / gpsd | ✅ |
| Wondom JAB5 Amp | I2S | 🔲 Planned |
| Video Grabber | USB V4L2 | 🔲 Planned |
| vLinker FS USB | OBD-II / ELM327 | 🔲 Planned |
| RTL-SDR Blog v4 | DAB+ | 🔲 Planned |
| Victron SmartShunt | VE.Direct | 🔲 Planned |
| Victron Smart Solar | VE.Direct | 🔲 Planned |
| Victron Orion Smart | BLE | 🔲 Planned |

## Project Structure

```
services/           # Systemd services and their scripts
  launcher/         # start-dash.sh — cage + waydroid + GPS
  display/          # DRM DPMS daemon
  usb-power/        # USB VBUS power control
  gps/              # GPS reflector + legacy service files
system/             # Boot config, apt pinning, DT overlays
deploy/             # deploy.sh, install.sh, backup.sh, boot-fix.sh
scripts/            # Debug and utility scripts
archive/            # Historical script versions (GPS evolution)
docs/               # Hardware docs, boot recovery, experiments
```

## ⚠️ Important: Kernel Safety

**Never run `apt upgrade` without checking held packages first!**

```bash
make apt-hold        # Pin kernel/u-boot/firmware packages
apt-mark showhold    # Verify they're held
```

See [docs/boot-recovery.md](docs/boot-recovery.md) for the full story.
