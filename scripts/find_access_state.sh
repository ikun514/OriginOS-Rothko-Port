#!/system/bin/sh
echo "=== /data/system entries matching access/permission/appop ==="
ls -la /data/system/ | grep -iE 'access|permission|appop' 
echo "=== /data/system/permission dir ==="
ls -la /data/system/permission/ 2>/dev/null | head -20
echo "=== find access files under /data ==="
find /data -xdev -maxdepth 3 -name '*access*' 2>/dev/null | head -20
echo "=== UTF-16 style grep in appops_accesses.xml ==="
grep -a -o -E 'M.I.U.I.:.1.0.0.0.8' /data/system/appops_accesses.xml 2>/dev/null | head -3
echo "=== search all small files in /data/system for utf16 MIUI ==="
for f in $(find /data/system -maxdepth 2 -type f -size -8M 2>/dev/null); do
  if grep -aq -E 'M.I.U.I.:.1.0.0.0.8' "$f" 2>/dev/null; then echo "HIT: $f"; fi
done
echo DONE
