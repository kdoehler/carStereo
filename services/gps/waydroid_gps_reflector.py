import subprocess
import json
import time

def reflect_gps():
    print("Initializing persistent Waydroid shell...")
    shell = subprocess.Popen(
        ["sudo", "waydroid", "shell"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    print("Connecting to gpsd stream...")
    gps_proc = subprocess.Popen(['gpspipe', '-w'], stdout=subprocess.PIPE, text=True)

    last_update = 0
    try:
        for line in gps_proc.stdout:
            try:
                data = json.loads(line)
            except: continue

            if data.get('class') == 'TPV':
                lat, lon = data.get('lat'), data.get('lon')
                curr = time.time()
                
                if lat and lon and (curr - last_update >= 1.0):
                    alt = data.get('alt', 0.0)
                    spd = data.get('speed', 0.0)
                    
                    # 'track' is your direction/compass heading in degrees (0-360)
                    brg = data.get('track', 0.0) 
                    
                    # 'eph' is the estimated heading error (accuracy of the compass)
                    # If the GPS doesn't provide it, we default to a reasonable 5.0 degrees
                    brg_acc = data.get('eph', 5.0)

                    # We include 'bearing' for the map rotation
                    cmd = (
                        f'am start-foreground-service --user 0 '
                        f'-n io.appium.settings/.LocationService '
                        f'--es longitude "{lon}" --es latitude "{lat}" --es altitude "{alt}" '
                        f'--es speed "{spd}" --es bearing "{brg}" --es bearingAccuracy "{brg_acc}"\n'
                    )
                    
                    shell.stdin.write(cmd)
                    shell.stdin.flush()
                    
                    last_update = curr
                    print(f"Pushed: {lat}, {lon} | Heading: {brg}°")

    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        gps_proc.terminate()
        shell.terminate()

if __name__ == "__main__":
    reflect_gps()
