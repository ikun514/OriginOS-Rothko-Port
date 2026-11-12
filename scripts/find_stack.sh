#!/system/bin/sh
echo "=== FATAL EXCEPTION blocks in main log ==="
logcat -b main -d 2>/dev/null | grep -n -B2 -A25 "Unknown operation string" | tail -80
echo "=== crash buffer ==="
logcat -b crash -d 2>/dev/null | tail -40
echo "=== system buffer around exception ==="
logcat -b system -d 2>/dev/null | grep -A20 "Unknown operation string" | tail -40
echo DONE
