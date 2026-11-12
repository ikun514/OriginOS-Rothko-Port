#!/system/bin/sh
M=/data/local/tmp/work/mntv
echo "=== rc service block ==="
grep -A8 -E '^service ' $M/etc/init/vendor.vivo.hardware.vibrator.custom.service.rc 2>/dev/null
echo "=== vintf manifest ==="
cat $M/etc/vintf/manifest/vendor.vivo.hardware.vibrator.custom.service.xml 2>/dev/null
echo "=== ldd-ish deps (readelf NEEDED) ==="
readelf -d $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service 2>/dev/null | grep NEEDED
echo "=== try run with vivo vendor LD path ==="
export LD_LIBRARY_PATH=$M/lib64:$M/lib64/hw
cd /
setsid $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service > /data/local/tmp/vibhal/run3.log 2>&1 &
sleep 5
echo "--- log ---"
cat /data/local/tmp/vibhal/run3.log 2>/dev/null
echo "--- ps ---"
ps -A -o PID,NAME 2>/dev/null | grep -i -E 'vibr|richtap|aac'
echo "--- service list ---"
service list 2>/dev/null | grep -i -E 'richtap|vivo.hardware.vibrator|aac'
echo DONE
