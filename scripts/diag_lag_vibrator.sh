#!/system/bin/sh
echo "===== D-state tasks ====="
ps -A -o PID,STAT,NAME 2>/dev/null | awk '$2 ~ /D/ {print}' | head -40
echo "count=$(ps -A -o STAT 2>/dev/null | grep -c '^D')"
echo
echo "===== stacks of D tasks (first 5) ====="
for p in $(ps -A -o PID,STAT 2>/dev/null | awk '$2 ~ /D/ {print $1}' | head -5); do
  echo "--- pid $p $(cat /proc/$p/comm 2>/dev/null)"
  cat /proc/$p/stack 2>/dev/null | head -6
done
echo
echo "===== vibrator services ====="
service list 2>/dev/null | grep -iE 'vibrat|haptic|rich'
echo "init.svc.vibratorfeature=$(getprop init.svc.vibratorfeature-hal-service)"
echo
echo "===== framework vibrator errors in logcat ====="
logcat -d -b all -t 3000 2>/dev/null | grep -iE 'vibrat|VibratorManager|haptic' | tail -25
echo
echo "===== slow operations / ANR-ish in logcat ====="
logcat -d -b all -t 4000 2>/dev/null | grep -iE 'ANR in|Slow dispatch|Slow operation|took [0-9]{4,}ms|Watchdog' | tail -20
echo
echo "===== gfx / jank stats ====="
dumpsys gfxinfo 2>/dev/null | head -20
echo
echo "===== top D-state io ====="
top -b -n 1 -m 15 -o %CPU,STAT,ARGS 2>/dev/null | head -22
echo DONE
