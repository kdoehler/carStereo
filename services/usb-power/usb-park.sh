#!/bin/bash
# USB VBUS power control for parked mode
# Cuts all USB power (display, hub, peripherals) without touching DWC3
# Usage: sudo usb-park.sh [off|on]

EHCI1=fc800000.usb
EHCI2=fc880000.usb
OHCI1=fc840000.usb
OHCI2=fc8c0000.usb
REG=regulator-vcc5v0-host

case "$1" in
  off)
    echo '=== USB PARK: POWERING OFF ==='
    echo $EHCI1 > /sys/bus/platform/drivers/ehci-platform/unbind
    echo $EHCI2 > /sys/bus/platform/drivers/ehci-platform/unbind
    echo $OHCI1 > /sys/bus/platform/drivers/ohci-platform/unbind
    echo $OHCI2 > /sys/bus/platform/drivers/ohci-platform/unbind
    # Unbind regulator last - GPIO goes low, VBUS cuts
    echo $REG > /sys/bus/platform/drivers/reg-fixed-voltage/unbind
    echo '=== USB OFF ==='
    ;;
  on)
    echo '=== USB PARK: POWERING ON ==='
    # Regulator first - GPIO goes high, VBUS up before any controller inits
    echo $REG > /sys/bus/platform/drivers/reg-fixed-voltage/bind
    sleep 1
    # Verify regulator came back before proceeding
    REG_STATE=$(cat /sys/class/regulator/regulator.8/state 2>/dev/null)
    echo "regulator: $REG_STATE"
    if [ -z "$REG_STATE" ]; then
      echo 'ERROR: regulator did not rebind - aborting'
      exit 1
    fi
    sleep 0.5
    echo $EHCI1 > /sys/bus/platform/drivers/ehci-platform/bind
    echo $EHCI2 > /sys/bus/platform/drivers/ehci-platform/bind
    echo $OHCI1 > /sys/bus/platform/drivers/ohci-platform/bind
    echo $OHCI2 > /sys/bus/platform/drivers/ohci-platform/bind
    echo '=== USB ON ==='
    ;;
  *)
    echo "Usage: $0 [off|on]"
    exit 1
    ;;
esac
