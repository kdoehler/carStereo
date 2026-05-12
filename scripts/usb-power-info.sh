#!/bin/bash
# Show USB devices with autosuspend state and power status

echo "=== USB Device Power States ==="
echo "BUS-DEV | control | runtime_status | autosuspend_delay_ms | product"
echo "--------|---------|----------------|---------------------|--------"

for dev in /sys/bus/usb/devices/*/; do
    busdev=$(basename "$dev")
    # Skip interfaces (only physical devices)
    [[ "$busdev" == *:* ]] && continue

    product=$(cat "$dev/product" 2>/dev/null || echo "?")
    ctrl=$(cat "$dev/power/control" 2>/dev/null || echo "?")
    stat=$(cat "$dev/power/runtime_status" 2>/dev/null || echo "?")
    delay=$(cat "$dev/power/autosuspend_delay_ms" 2>/dev/null || echo "?")

    echo "$busdev | $ctrl | $stat | ${delay}ms | $product"
done

echo ""
echo "=== Global USB autosuspend default ==="
cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null || echo "not available"

echo ""
echo "=== Hub port power state ==="
for hub in /sys/bus/usb/devices/*/; do
    busdev=$(basename "$hub")
    [[ "$busdev" == *:* ]] && continue
    class=$(cat "$hub/bDeviceClass" 2>/dev/null)
    if [ "$class" = "09" ]; then
        product=$(cat "$hub/product" 2>/dev/null || echo "hub")
        stat=$(cat "$hub/power/runtime_status" 2>/dev/null)
        echo "HUB $busdev ($product): $stat"
        # Check each port on this hub
        for port in "$hub"power/usb*/; do
            [ -d "$port" ] && echo "  port: $(basename $port)"
        done
    fi
done
