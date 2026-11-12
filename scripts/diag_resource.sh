#!/system/bin/sh
echo "===== load / count ====="
cat /proc/loadavg
echo "processes=$(ps -A 2>/dev/null | wc -l)"
echo "threads-max=$(cat /proc/sys/kernel/threads-max 2>/dev/null)"
echo "pid-max=$(cat /proc/sys/kernel/pid_max 2>/dev/null)"
echo
echo "===== cgroup pids ====="
for f in /sys/fs/cgroup/pids.max /sys/fs/cgroup/pids.current /sys/fs/cgroup/system/pids.max /sys/fs/cgroup/system/pids.current; do
  [ -f "$f" ] && echo "$f=$(cat $f)"
done
find /sys/fs/cgroup -maxdepth 3 -name 'pids.current' 2>/dev/null | head -10 | while read f; do echo "$f=$(cat $f 2>/dev/null)"; done
echo
echo "===== top processes by thread count ====="
for p in $(ps -A -o PID 2>/dev/null | tail -n +2 | head -400); do
  n=$(ls /proc/$p/task 2>/dev/null | wc -l)
  echo "$n $p $(cat /proc/$p/comm 2>/dev/null)"
done | sort -rn | head -20
echo
echo "===== meminfo ====="
cat /proc/meminfo | head -12
echo
echo "===== recent OOM / thread errors ====="
logcat -d -b all -t 4000 2>/dev/null | grep -iE "pthread_create|OutOfMemoryError|Failed to create thread|low memory|lmkd|kill" | tail -25
echo
echo "===== crash-looping processes ====="
logcat -d -b crash -t 200 2>/dev/null | grep -E "Process:|FATAL EXCEPTION" | tail -20
echo DONE
