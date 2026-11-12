#!/system/bin/sh
echo "=== /odm/etc/build.prop key lines ==="
ls -l /odm/etc/build.prop
grep -E 'ro\.product\.odm\.(brand|manufacturer|model|name|marketname)|ro\.product\.(brand|model|device|name)=|ro\.vivo' /odm/etc/build.prop 2>/dev/null | head -25
echo "=== rothko product overlay (if image mounted) ==="
R=/data/local/tmp/rothko_product_a.img
M=/data/local/tmp/mnt_rothko_product
mkdir -p $M
if [ -f "$R" ]; then
  chcon u:object_r:system_file:s0 "$R" 2>/dev/null
  mount -t erofs -o ro "$R" "$M" 2>/dev/null || { chcon u:object_r:system_file:s0 "$R"; mount -t erofs -o ro "$R" "$M"; }
  echo "mount rc=$?"
  ls "$M" 2>/dev/null | head
  L="$M"
  [ -d "$M/system/overlay" ] && L="$M/system"
  echo "using $L"
  ls "$L/overlay/" 2>/dev/null | head -40
  echo "--- looking for Device*Overlay ---"
  find "$L/overlay" -maxdepth 2 -iname '*Device*Overlay*' 2>/dev/null | head -10
  echo "--- copy candidates ---"
  mkdir -p /data/local/tmp/portfix/overlays
  for f in $(find "$L/overlay" -maxdepth 2 -iname '*Device*Overlay*' 2>/dev/null); do
    cp -f "$f" /data/local/tmp/portfix/overlays/ 2>/dev/null && echo "copied $f"
  done
  umount "$M"
else
  echo "rothko product image not present"
fi
echo DONE
