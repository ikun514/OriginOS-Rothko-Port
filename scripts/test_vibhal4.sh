#!/system/bin/sh
M=/data/local/tmp/work/mntv
echo "=== expected service names in libvivo_servers.so ==="
strings /system/lib64/libvivo_servers.so 2>/dev/null | grep -iE 'richtap|vibrator|aac' | head -20
echo "=== strings in vivo vibrator HAL ==="
strings $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service 2>/dev/null | grep -iE 'richtap|vibrator|aac|instance|default' | head -20
echo "=== run with env (foreground, 8s timeout) ==="
export LD_LIBRARY_PATH=$M/lib64:$M/lib64/hw
export RICHTAP_DEVICE_PATH='/dev/vivo_haptic;/dev/vivo_haptic_vice'
export ENV_RICHTAP_CONFIG_PATH='/odm/etc/aac_richtap.config;/odm/etc/aac_richtap_1.config'
cd /
timeout 8 $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service
echo "exit=$?"
echo "=== after run: service list ==="
service list 2>/dev/null | grep -iE 'richtap|vibrator' 
echo "=== dev nodes ==="
ls -l /dev/vivo_haptic* /sys/class/leds/vibrator 2>&1 | head -5
echo DONE
