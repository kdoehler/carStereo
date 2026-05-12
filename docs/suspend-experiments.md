# Suspend & Sleep Experiments

> **TL;DR**: S3 suspend does not work reliably on the RK3588. We abandoned it in favor of a software-based "Parked Mode" using MOSFET USB power-kill + DRM DPMS display off + CPU clock scaling.

---

## Goal

Reduce power consumption when the van is parked (engine off) to avoid draining the leisure battery. Ideally sub-1W idle, or at least significantly reduced from the ~5-8W active draw.

## Approach 1: `systemctl suspend` (standard Linux S3)

**Result**: ❌ Does not work.

Armbian on the Rock 5B doesn't reliably enter S3 sleep. The system either fails to suspend entirely, or suspends but never wakes. The RK3588 SoC's suspend path in mainline Linux has significant gaps — many platform drivers don't implement proper suspend/resume callbacks.

## Approach 2: Diskless Suspend (`deep-sleep.sh`)

**Concept**: Manually unbind hardware that can't survive suspend, then use `rtcwake -m freeze` (s2idle) instead of true S3. On wake, rebind everything.

### What the script does:
```bash
# 1. Lock binaries into RAM (they live on NVMe which we're about to detach)
cat /usr/sbin/rtcwake /usr/bin/lspci /usr/bin/awk /usr/bin/tee > /dev/null

# 2. Unbind GPU (Panthor driver)
echo "fb000000.gpu" > /sys/bus/platform/drivers/panthor/unbind

# 3. Unbind USB controllers
echo "xhci-hcd.0.auto" > /sys/bus/platform/drivers/xhci-hcd/unbind
echo "xhci-hcd.8.auto" > /sys/bus/platform/drivers/xhci-hcd/unbind

# 4. Unbind NVMe
echo "$NVME_PCI" > /sys/bus/pci/drivers/nvme/unbind

# 5. Enter s2idle with 15-second auto-wake (for testing)
rtcwake -d /dev/rtc0 -m freeze -s 15

# 6. Rebind everything on wake
echo "$NVME_PCI" > /sys/bus/pci/drivers/nvme/bind
echo "fb000000.gpu" > /sys/bus/platform/drivers/panthor/bind
echo "xhci-hcd.0.auto" > /sys/bus/platform/drivers/xhci-hcd/bind
echo "xhci-hcd.8.auto" > /sys/bus/platform/drivers/xhci-hcd/bind
```

**Result**: ⚠️ Partially works. The system does enter `freeze` and the RTC wakeup fires, but:
- GPU rebind fails intermittently → black screen after wake
- NVMe rebind sometimes hangs → filesystem panic
- No user-triggered wake mechanism (RTC only)

### Source: [`scripts/deep-sleep.sh`](../scripts/deep-sleep.sh)

## Approach 3: DT Overlays to Improve Suspend

Two device tree overlays were created to reduce the suspend surface:

### `fix-suspend.dts` — Disable NPU and Video Codecs

Disables hardware blocks that lack proper suspend/resume drivers:

```dts
fragment@0 { target-path = "/npu@fdab0000";           __overlay__ { status = "disabled"; }; };
fragment@1 { target-path = "/video-codec@fdba4000";    __overlay__ { status = "disabled"; }; };
fragment@2 { target-path = "/video-codec@fdba8000";    __overlay__ { status = "disabled"; }; };
fragment@3 { target-path = "/video-codec@fdbac000";    __overlay__ { status = "disabled"; }; };
fragment@4 { target-path = "/video-codec@fdc40100";    __overlay__ { status = "disabled"; }; };
```

**Result**: Reduced the number of suspend errors in `dmesg`, but didn't fix the core problem (GPU + NVMe).

### Source: [`system/overlays/fix-suspend.dts`](../system/overlays/fix-suspend.dts)

### `s3-wake.dts` — GPIO Wakeup Button

Registers a `gpio-keys` wakeup source on GPIO0 pin 14 (active low, debounced):

```dts
gpio-keys {
    compatible = "gpio-keys";
    s3_wakeup {
        label = "S3 Wakeup Button";
        gpios = <&gpio0 14 1>;     /* GPIO_ACTIVE_LOW */
        linux,code = <143>;         /* KEY_WAKEUP */
        wakeup-source;
        debounce-interval = <50>;
    };
};
```

**Testing**: Verified with `gpiomon` that the button state changes were detected on both gpiochip0 lines 13/14 and gpiochip4 lines 0–6. However, the wakeup never triggered from actual s2idle/freeze state — the interrupt isn't being serviced during suspend.

### Source: [`system/overlays/s3-wake.dts`](../system/overlays/s3-wake.dts)

## Approach 4: Custom DTB

A custom device tree (`rk3588-rock-5b-custom.dtb`) was built and loaded via `fdtfile=` in armbianEnv.txt. This was used alongside the overlays above. The custom DTB + overlay combination was referenced in the backup config:

```
fdtfile=rockchip/rk3588-rock-5b-custom.dtb
```

This was eventually removed and the system reverted to the stock DTB (`dtb/` symlink to the standard Armbian DTB directory).

## Conclusion: Why We Abandoned Suspend

| Issue | Detail |
|---|---|
| RK3588 S3 support | Incomplete in mainline Linux — many platform drivers don't handle suspend/resume |
| GPU (Panthor) | Driver crashes on rebind after suspend |
| NVMe | PCIe rebind unreliable — risks filesystem corruption |
| GPIO wakeup | Interrupts not serviced during freeze state |
| Complexity | Too many manual unbind/rebind steps with too many failure modes |

## The Alternative: Parked Mode (Phase 1)

Instead of trying to suspend, we keep the system running but minimize power:

1. **MOSFET switch** kills USB hub power (all peripherals off)
2. **DRM DPMS** turns display off (backlight kill via `drm-dpms-daemon.py`)
3. **CPU scaling** → `powersave` governor at minimum frequency (408MHz)
4. **Waydroid freeze** → container is already configured with `suspend_action=freeze`

Estimated power draw: ~2W (vs ~5-8W active). Not as good as true S3 (<1W), but **reliable and recoverable**.

See: Phase 1 in the [implementation plan](../README.md).
