#!/system/bin/sh
M=/data/local/tmp/work/mntv
export LD_LIBRARY_PATH=$M/lib64:$M/lib64/hw
export RICHTAP_DEVICE_PATH='/dev/vivo_haptic;/dev/vivo_haptic_vice'
export ENV_RICHTAP_CONFIG_PATH='/odm/etc/aac_richtap.config;/odm/etc/aac_richtap_1.config'
cd /
setsid $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service > /data/local/tmp/vibhal/bg.log 2>&1 &
sleep 5
echo "=== ps ==="
ps -A -o PID,NAME 2>/dev/null | grep -iE 'vibr|richtap'
echo "=== service list (all) ==="
service list 2>/dev/null | grep -iE 'richtap|vibrator|aac' 
echo "=== logcat tail for HAL ==="
logcat -d -s vendor.vibrator-default 2>/dev/null | tail -20
logcat -d 2>/dev/null | grep -iE 'Richtap|vibrator-default|vivo_haptic' | tail -20
echo "=== bg.log ==="
cat /data/local/tmp/vibhal/bg.log 2>/dev/null | tail -20
echo DONE
