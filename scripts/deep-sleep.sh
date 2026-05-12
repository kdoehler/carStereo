#!/bin/bash

# 1. Check for root immediately
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo ./deep-sleep.sh)"
  exit
fi

# 2. Fix the PCI Address variable
# We grab only the last 7 characters to avoid the 0000:0000 error
NVME_PCI="0000:$(lspci | grep -i nvme | awk '{print $1}')"

# 3. Lock binaries into RAM cache
cat /usr/sbin/rtcwake /usr/bin/lspci /usr/bin/awk /usr/bin/tee > /dev/null

echo "--- Preparing for Diskless Suspend ---"

# 4. Unbind GPU & USB
echo "fb000000.gpu" > /sys/bus/platform/drivers/panthor/unbind
echo "xhci-hcd.0.auto" > /sys/bus/platform/drivers/xhci-hcd/unbind
echo "xhci-hcd.8.auto" > /sys/bus/platform/drivers/xhci-hcd/unbind

# 5. Unbind NVMe
echo "Ejecting NVMe at $NVME_PCI..."
echo "$NVME_PCI" > /sys/bus/pci/drivers/nvme/unbind

# 6. Trigger Sleep (The execution stays in RAM)
echo "Disk is detached. Suspending now..."
rtcwake -d /dev/rtc0 -m freeze -s 15

# 7. Wakeup Recovery (Physical addresses only)
echo "Waking up. Re-binding hardware..."
echo "$NVME_PCI" > /sys/bus/pci/drivers/nvme/bind
sleep 2
echo "fb000000.gpu" > /sys/bus/platform/drivers/panthor/bind
echo "xhci-hcd.0.auto" > /sys/bus/platform/drivers/xhci-hcd/bind
echo "xhci-hcd.8.auto" > /sys/bus/platform/drivers/xhci-hcd/bind

echo "System Restored."
