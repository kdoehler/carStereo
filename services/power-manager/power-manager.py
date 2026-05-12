#!/usr/bin/env python3
"""
power-manager.py — Ignition-aware power state daemon for Rock 5B camper head unit.

Monitors the ACC/ignition signal via GPIO (Pololu D24V5F3 → GPIO3_A4, Pin 16)
and transitions between DRIVING and PARKED modes.

USB power control uses uhubctl to cut VBUS on the EHCI root hub port,
which physically powers off the entire USB hub tree (saves ~0.86W).
Devices re-enumerate cleanly on power restore.


Hardware:
  - Pololu D24V5F3: steps ignition 12V → 3.3V for GPIO input
  - GPIO: gpiochip3, line 4 (GPIO3_A4 = GPIO number 100, physical pin 16 on 40-pin header)
  - Pin 16 has no default alternate function — pure GPIO, safe for input
  - Ignition ON  → GPIO reads 1 → DRIVING mode
  - Ignition OFF → GPIO reads 0 → PARKED mode

DRIVING mode (ignition ON):
  - Display ON (DRM DPMS)
  - USB controllers bound (peripherals powered)
  - CPU governor: ondemand (full performance)

PARKED mode (ignition OFF, after grace period):
  - Display OFF (DRM DPMS via drm-dpms-daemon.py)
  - USB controllers unbound (MOSFET kills VBUS — optional)
  - CPU governor: powersave (408 MHz minimum)
  - Waydroid: freeze container (suspend_action=freeze)

Safety:
  - Grace period (default 30s) before entering parked mode to avoid
    false triggers during engine cranking or brief key-off moments
  - Hysteresis: ignition must be stable for the full grace period
  - USB park is optional (disabled by default) — enable only when
    MOSFET hardware is installed

Usage:
  sudo python3 power-manager.py [--grace-seconds 30] [--usb-park] [--dry-run]

Signals:
  SIGTERM / SIGINT: restore DRIVING mode and exit cleanly
"""

import argparse
import logging
import os
import signal
import subprocess
import sys
import time
from enum import Enum
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GPIO_CHIP = "gpiochip3"
GPIO_LINE = "4"  # GPIO3_A4 = physical pin 16 (GPIO number 100)

# CPU frequency policies on RK3588 (LITTLE, big, BIG)
CPU_POLICIES = ["policy0", "policy4", "policy6"]
GOVERNOR_DRIVING = "ondemand"
GOVERNOR_PARKED = "powersave"

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
# USB power control via uhubctl (EHCI root hub port power switching)
USB_HUB_LOCATION = "3"  # EHCI root hub (Bus 003)
USB_HUB_PORT = "1"      # Port 1 (Terminus 4-port hub and all downstream)
DRM_DPMS_SCRIPT = SCRIPT_DIR.parent / "display" / "drm-dpms-daemon.py"

# Logging
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
LOG_DATEFMT = "%Y-%m-%d %H:%M:%S"


class PowerState(Enum):
    DRIVING = "DRIVING"
    PARKED = "PARKED"
    TRANSITIONING = "TRANSITIONING"


# ---------------------------------------------------------------------------
# GPIO
# ---------------------------------------------------------------------------

def read_ignition() -> bool:
    """Read the ignition GPIO pin. Returns True if ignition is ON."""
    try:
        result = subprocess.run(
            ["gpioget", GPIO_CHIP, GPIO_LINE],
            capture_output=True, text=True, timeout=5
        )
        value = result.stdout.strip()
        return value == "1"
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logging.error(f"Failed to read GPIO: {e}")
        return False


# ---------------------------------------------------------------------------
# Display control
# ---------------------------------------------------------------------------

# We track the dpms-off process so we can kill it to restore the display
_dpms_proc = None


def display_off():
    """Turn display off using drm-dpms-daemon.py (blocks until killed)."""
    global _dpms_proc
    if _dpms_proc and _dpms_proc.poll() is None:
        logging.debug("Display already off")
        return

    if not DRM_DPMS_SCRIPT.exists():
        logging.warning(f"DRM DPMS script not found: {DRM_DPMS_SCRIPT}")
        return

    logging.info("Display → OFF")
    _dpms_proc = subprocess.Popen(
        ["python3", str(DRM_DPMS_SCRIPT), "off"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def display_on():
    """Restore display by killing the dpms-off daemon (which restores on exit)."""
    global _dpms_proc
    if _dpms_proc and _dpms_proc.poll() is None:
        logging.info("Display → ON (killing DPMS daemon)")
        _dpms_proc.terminate()
        try:
            _dpms_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            _dpms_proc.kill()
        _dpms_proc = None
    else:
        # One-shot restore in case daemon isn't running
        if DRM_DPMS_SCRIPT.exists():
            logging.info("Display → ON (one-shot)")
            subprocess.run(
                ["python3", str(DRM_DPMS_SCRIPT), "on"],
                timeout=10
            )


# ---------------------------------------------------------------------------
# CPU governor
# ---------------------------------------------------------------------------

def set_cpu_governor(governor: str):
    """Set CPU frequency governor for all policy groups."""
    for policy in CPU_POLICIES:
        path = f"/sys/devices/system/cpu/cpufreq/{policy}/scaling_governor"
        try:
            with open(path, "w") as f:
                f.write(governor)
            logging.debug(f"CPU {policy} → {governor}")
        except OSError as e:
            logging.error(f"Failed to set governor for {policy}: {e}")
    logging.info(f"CPU governor → {governor}")


# ---------------------------------------------------------------------------
# USB power (uhubctl port power switching)
# ---------------------------------------------------------------------------

def usb_power(on: bool):
    """Control USB hub power via uhubctl.

    Cuts/restores VBUS on the EHCI root hub port, which powers off/on the
    entire downstream hub tree (Terminus 4-port → 7-port → all devices).
    Saves ~0.86W when off. Devices re-enumerate cleanly on restore.
    """
    action = "on" if on else "off"
    logging.info(f"USB → {action.upper()} (uhubctl hub {USB_HUB_LOCATION} port {USB_HUB_PORT})")
    try:
        subprocess.run(
            ["uhubctl", "-l", USB_HUB_LOCATION, "-p", USB_HUB_PORT, "-a", action],
            timeout=10, check=True, capture_output=True
        )
    except FileNotFoundError:
        logging.error("uhubctl not installed — USB power control unavailable")
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
        logging.error(f"USB power control failed: {e}")


# ---------------------------------------------------------------------------
# Waydroid container control
# ---------------------------------------------------------------------------

def waydroid_freeze():
    """Freeze the Waydroid container to save CPU/memory."""
    logging.info("Waydroid → FREEZE")
    try:
        subprocess.run(
            ["waydroid", "container", "freeze"],
            timeout=10, capture_output=True
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logging.warning(f"Waydroid freeze failed: {e}")


def waydroid_unfreeze():
    """Unfreeze the Waydroid container."""
    logging.info("Waydroid → UNFREEZE")
    try:
        subprocess.run(
            ["waydroid", "container", "unfreeze"],
            timeout=10, capture_output=True
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        logging.warning(f"Waydroid unfreeze failed: {e}")


# ---------------------------------------------------------------------------
# State transitions
# ---------------------------------------------------------------------------

def enter_parked(usb_park_enabled: bool, dry_run: bool):
    """Transition to PARKED mode."""
    logging.info("━━━ Entering PARKED mode ━━━")
    if dry_run:
        logging.info("[DRY RUN] Would: display off, CPU powersave, waydroid freeze")
        return

    display_off()
    set_cpu_governor(GOVERNOR_PARKED)
    waydroid_freeze()
    if usb_park_enabled:
        usb_power(on=False)


def enter_driving(usb_park_enabled: bool, dry_run: bool):
    """Transition to DRIVING mode."""
    logging.info("━━━ Entering DRIVING mode ━━━")
    if dry_run:
        logging.info("[DRY RUN] Would: USB on, CPU ondemand, waydroid unfreeze, display on")
        return

    # USB first (peripherals need time to enumerate)
    if usb_park_enabled:
        usb_power(on=True)
        time.sleep(3)  # Let USB devices re-enumerate

    set_cpu_governor(GOVERNOR_DRIVING)
    waydroid_unfreeze()
    display_on()


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

running = True


def on_signal(signum, frame):
    global running
    logging.info(f"Received signal {signum}, shutting down...")
    running = False


def main():
    global running

    parser = argparse.ArgumentParser(description="Ignition-aware power manager")
    parser.add_argument(
        "--grace-seconds", type=int, default=30,
        help="Seconds to wait after ignition off before parking (default: 30)"
    )
    parser.add_argument(
        "--usb-park", action="store_true",
        help="Enable USB VBUS power control via uhubctl (cuts port power to save ~0.86W)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Log state transitions without executing them"
    )
    parser.add_argument(
        "--poll-interval", type=float, default=1.0,
        help="GPIO poll interval in seconds (default: 1.0)"
    )
    parser.add_argument(
        "--log-level", default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)"
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format=LOG_FORMAT, datefmt=LOG_DATEFMT
    )

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    # Verify GPIO is readable
    logging.info(f"Power Manager starting (GPIO: {GPIO_CHIP}/{GPIO_LINE}, "
                 f"grace: {args.grace_seconds}s, USB park: {args.usb_park})")

    ignition = read_ignition()
    if ignition:
        state = PowerState.DRIVING
        logging.info(f"Initial state: DRIVING (ignition is ON)")
    else:
        state = PowerState.DRIVING  # Start in driving, let the grace period handle it
        logging.info(f"Initial state: DRIVING (ignition is OFF — grace period will trigger)")

    off_since = None  # Timestamp when ignition first went off

    while running:
        ignition = read_ignition()

        if state == PowerState.DRIVING:
            if ignition:
                # Still driving — reset any pending off timer
                off_since = None
            else:
                # Ignition just went off (or still off)
                if off_since is None:
                    off_since = time.time()
                    logging.info(f"Ignition OFF — grace period started ({args.grace_seconds}s)")

                elapsed = time.time() - off_since
                if elapsed >= args.grace_seconds:
                    # Grace period expired — park it
                    enter_parked(args.usb_park, args.dry_run)
                    state = PowerState.PARKED
                    off_since = None
                else:
                    remaining = args.grace_seconds - elapsed
                    if int(remaining) % 10 == 0 and remaining > 0:
                        logging.debug(f"Parking in {int(remaining)}s...")

        elif state == PowerState.PARKED:
            if ignition:
                # Ignition is back — wake up immediately (no grace period)
                logging.info("Ignition ON — waking up immediately")
                enter_driving(args.usb_park, args.dry_run)
                state = PowerState.DRIVING
                off_since = None

        time.sleep(args.poll_interval)

    # Clean exit — always restore to driving mode
    logging.info("Shutting down — restoring DRIVING mode")
    if state == PowerState.PARKED and not args.dry_run:
        enter_driving(args.usb_park, args.dry_run)
    logging.info("Power Manager stopped")


if __name__ == "__main__":
    main()
