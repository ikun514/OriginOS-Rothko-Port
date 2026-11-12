#!/system/bin/sh
echo "===== uptime / boot time ====="
uptime; getprop ro.boottime.init; date
echo
echo "===== crash buffer (full tail 120) ====="
logcat -d -b crash -t 120 2>/dev/null | tail -90
echo
echo "===== newest tombstones ====="
ls -lt /data/tombstones 2>/dev/null | head -8
for f in $(ls -t /data/tombstones/tombstone_0[0-9] 2>/dev/null | head -2); do
  echo "--- $f"
  head -14 "$f" 2>/dev/null
  grep -m1 -A3 "Abort message" "$f" 2>/dev/null
done
echo
echo "===== BT error lines around death ====="
logcat -d -b all -t 3000 2>/dev/null | grep -iE "bluetooth.*(error|fail|died|crash|abort)|btif|btsnoop|hci.*(timeout|fail)" | tail -40
echo
echo "===== system_server crash? ====="
logcat -d -b all -t 5000 2>/dev/null | grep -E "FATAL EXCEPTION IN SYSTEM PROCESS|*** FATAL" -A4 | head -30
echo DONE
