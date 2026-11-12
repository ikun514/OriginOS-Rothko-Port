#!/system/bin/sh
echo "=== grep MIUI:10008 under /data/system ==="
grep -rl "MIUI:10008" /data/system 2>/dev/null | head -10
echo "=== grep MIUI:10008 under /data/misc ==="
grep -rl "MIUI:10008" /data/misc 2>/dev/null | head -10
echo "=== appops files ==="
find /data -maxdepth 5 -name '*appop*' 2>/dev/null | head -20
echo "=== /data/system/users/0 listing ==="
ls /data/system/users/0/ 2>/dev/null | head -40
echo "=== /data/system files (a*) ==="
ls /data/system/ | grep -i '^a' | head -20
echo DONE
