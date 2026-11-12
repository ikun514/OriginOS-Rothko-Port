#!/system/bin/sh
for D in /data/misc /data/vendor /data/local /data/adb /data/user_de /data/system /data/user /data/resource-cache /data/app; do
  echo "=== grep in $D ==="
  grep -ral "MIUI:10008" "$D" 2>/dev/null | head -5
  grep -ral "MIUI:" "$D" 2>/dev/null | head -5
done
echo "=== packages with miui in name (data/app) ==="
ls /data/app 2>/dev/null | grep -i miui | head -10
echo DONE
