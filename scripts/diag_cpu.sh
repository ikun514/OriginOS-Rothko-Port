#!/system/bin/sh
echo "===== dumpsys cpuinfo (top) ====="
dumpsys cpuinfo 2>/dev/null | head -40
echo
echo "===== process start churn (last 5000 log lines) ====="
logcat -d -b all -t 5000 2>/dev/null | grep -oE "Start proc [0-9]+:[^ ]+" | awk '{print $NF}' | sort | uniq -c | sort -rn | head -15
echo
echo "===== crash churn by process ====="
logcat -d -b crash -t 400 2>/dev/null | grep -oE "Process: [^,]+" | sort | uniq -c | sort -rn | head -10
echo
echo "===== threads total ====="
cat /proc/loadavg
echo "procs=$(ps -A 2>/dev/null | wc -l)"
echo
echo "===== top 10 by threads ====="
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  n=$(ls /proc/$p/task 2>/dev/null | wc -l)
  [ "$n" -gt 80 ] && echo "$n $p $(cat /proc/$p/comm 2>/dev/null)"
done | sort -rn | head -15
echo DONE
