#!/system/bin/sh
echo "=== *.abx under /data ==="
find /data -xdev -name '*.abx' 2>/dev/null | head -20
echo "=== /data/misc dirs ==="
ls /data/misc/ 2>/dev/null | head -30
echo "=== appops_accesses.xml strings (first 40 lines with MIUI-ish) ==="
strings -a /data/system/appops_accesses.xml 2>/dev/null | grep -iE 'miui|app-op' | head -10
echo "=== appops dir discrete sample ==="
ls /data/system/appops/discrete/ 2>/dev/null | tail -3
T=$(ls -t /data/system/appops/discrete/ 2>/dev/null | head -1)
echo "sample file: $T"
strings -a "/data/system/appops/discrete/$T" 2>/dev/null | grep -iE 'miui|10008' | head -5
echo "=== any file in /data modified after 17:20 containing MIUI string ==="
find /data/system -maxdepth 2 -type f -newermt '2026-11-11 17:00' 2>/dev/null | head -0
grep -ral "MIUI" /data/system/appops 2>/dev/null | head -5
echo DONE
