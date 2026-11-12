#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnt $W/images
if [ ! -f $W/images/vendor.img ]; then
  echo "copying vendor.img from /sdcard (device-side cp)"
  time cp /sdcard/work/images/vendor.img $W/images/vendor.img
fi
chcon u:object_r:system_file:s0 $W/images/vendor.img
mount -t erofs -o ro $W/images/vendor.img $W/mnt
echo "mount rc=$?"
echo "=== vivo vendor top ==="
ls $W/mnt
echo "=== vivo vendor VINTF manifests ==="
ls $W/mnt/etc/vintf/manifest/ 2>/dev/null | sed 's/\.xml$//' | tr '\n' ' '
echo
echo "=== vivo vendor HAL impls count ==="
ls $W/mnt/lib64/hw 2>/dev/null | wc -l
ls $W/mnt/lib64/hw 2>/dev/null | head -100 | tr '\n' ' '
echo
echo "=== vivo vendor build.prop (key) ==="
grep -E '^(ro\.(build|product|vivo|vndk|treble|board|hardware|vendor\.vndk)|ro\.vivo\.)' $W/mnt/build.prop 2>/dev/null | head -50
echo "=== vivo vendor size top dirs ==="
du -sk $W/mnt/* 2>/dev/null | sort -n -r | head -12
umount $W/mnt
echo DONE
