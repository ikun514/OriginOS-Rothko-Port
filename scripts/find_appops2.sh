#!/system/bin/sh
echo "=== /data/system/appops ==="
ls -la /data/system/appops/ 2>/dev/null | head -20
echo "=== grep -a MIUI:10008 (system, binary) ==="
grep -ral "MIUI:10008" /data/system 2>/dev/null | head -10
echo "=== grep -a MIUI (system) ==="
grep -ral "MIUI:" /data/system 2>/dev/null | head -20
echo "=== dump head of appops_accesses.xml ==="
head -c 600 /data/system/appops_accesses.xml 2>/dev/null
echo
echo "=== any files in appops dir ==="
find /data/system/appops -maxdepth 2 -type f 2>/dev/null | head -20
echo DONE
