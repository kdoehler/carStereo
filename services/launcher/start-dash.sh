#!/bin/bash

# 1. Environment - Tell Cage to use the physical screen (DRM)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WLR_BACKENDS=drm
export WAYLAND_DISPLAY=wayland-0

# 2. Force Start the Container
sudo systemctl start waydroid-container

# 3. Wait for the Container (Rational timeout)
echo "Waiting for Waydroid..."
for i in {1..20}; do
    if sudo waydroid status | grep -q "RUNNING"; then
        break
    fi
    sleep 1
done

# 4. Handle Hardware & Unlock in background
(
    # 1. Wait for the 'Boot Completed' signal from Android
    # This is the secret—don't touch /dev until Android is fully settled
    until sudo waydroid shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
        sleep 2
    done
    waydroid shell appops set de.pilablu.gpsconnector android:mock_location allow
    waydroid shell settings put secure location_mode 3
    sudo python3 /home/ganimed/waydroid_gps_reflector.py > /home/ganimed/gps_reflector.log 2>&1 &

    # 3. The "Ghost" Trick: Tells Waydroid to treat this as real hardware
    # This is what makes the "Blue Dot" stable in Google Maps
    #sudo waydroid prop set persist.waydroid.gps_enabled true

    echo "GPS Bridge is hot. Van is ready."

) &

# 5. Launch UI
echo "Starting Graphics..."
exec cage -- waydroid show-full-ui > /home/ganimed/dash.log 2>&1
