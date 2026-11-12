#!/system/bin/sh
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  P=$(ps -A -o PID,NAME 2>/dev/null | grep -E 'system_server' | tr -d '\r' | tr '\n' ';')
  B=$(getprop sys.boot_completed)
  echo "t=$((i*5))s bc=$B ss=$P"
  sleep 5
done
echo "=== events: crash/died/proc ==="
logcat -b events -d 2>/dev/null | grep -E 'am_crash|am_proc_died|am_anr|am_kill|boot_progress' | tail -30
echo "=== main log: last 40 non-auditd ==="
logcat -b main -d 2>/dev/null | grep -v 'auditd' | tail -40
echo "=== crash buffer ==="
logcat -b crash -d 2>/dev/null | tail -15
echo DONE
