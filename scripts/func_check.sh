#!/system/bin/sh
echo "=== wifi ==="
getprop init.svc.wifi_hal; getprop init.svc.wpa_supplicant; getprop init.svc.hostapd
cmd wifi status 2>&1 | head -8
echo "=== bluetooth ==="
getprop init.svc.bluetooth; cmd bluetooth_manager get-state 2>&1 | head -3
echo "=== audio ==="
getprop init.svc.audioserver; getprop init.svc.audio-hal; getprop ro.vendor.audio.hifi
dumpsys media.audio_flinger 2>/dev/null | grep -E 'Output thread|Audio HAL|standby' | head -6
echo "=== camera ==="
getprop init.svc.cameraserver; getprop init.svc.camerahalserver
dumpsys media.camera 2>/dev/null | head -12
echo "=== sensors ==="
dumpsys sensorservice 2>/dev/null | head -18
echo "=== telephony ==="
getprop gsm.sim.state; getprop ro.telephony.default_network; getprop init.svc.mtkrild
dumpsys telephony.registry 2>/dev/null | head -8
echo "=== display ==="
dumpsys SurfaceFlinger 2>/dev/null | grep -E 'Display 0|refresh|mode' | head -6
echo "=== input/touch ==="
getprop ro.hardware.fp.fod
echo DONE
