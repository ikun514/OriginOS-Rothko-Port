#!/system/bin/sh
M=/data/local/tmp/work/mntv
ls $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service 2>/dev/null || echo "vendor img not mounted"
export LD_LIBRARY_PATH=$M/lib64:$M/lib64/hw
nohup $M/bin/hw/vendor.vivo.hardware.vibrator.custom.service > /data/local/tmp/vibhal/run2.log 2>&1 &
PID=$!
sleep 5
echo "pid=$PID alive=$(kill -0 $PID 2>/dev/null && echo yes || echo no)"
echo "--- log ---"
tail -20 /data/local/tmp/vibhal/run2.log 2>/dev/null
echo "--- services ---"
service list 2>/dev/null | grep -iE 'richtap|vibrator|custom' || echo "(no matching service)"
echo "--- boot state ---"
getprop sys.boot_completed
echo DONE
