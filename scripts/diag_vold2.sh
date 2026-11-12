#!/system/bin/sh
echo "===== find libblkid ====="
find /system /system_ext /product /vendor /odm /apex -name 'libblkid.so' 2>/dev/null | head -10
echo
echo "===== vold NEEDED libs ====="
readelf -d /system/bin/vold 2>/dev/null | grep NEEDED | head -30
echo
echo "===== linkerconfig paths for system namespace ====="
grep -n -A8 '\[system\]' /linkerconfig/ld.config.txt 2>/dev/null | head -30
echo
echo "===== try mount emulated volume ====="
sm mount 'emulated;0' 2>&1
sleep 2
sm list-volumes 2>&1
ls -l /storage/emulated/0 2>&1 | head -5
echo
echo "===== vold current pid / status ====="
echo "VOLD=$(getprop init.svc.vold) PID=$(pidof vold)"
echo DONE
