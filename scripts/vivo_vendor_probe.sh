#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnt
chcon u:object_r:system_file:s0 $W/images/vendor.img 2>/dev/null
mount -t erofs -o ro $W/images/vendor.img $W/mnt
echo "mount rc=$?"
echo "=== vivo vendor top ==="
ls $W/mnt
echo "=== vivo vendor VINTF manifests ==="
ls $W/mnt/etc/vintf/manifest/ 2>/dev/null | sed 's/\.xml$//' | tr '\n' ' '
echo
echo "=== vivo vendor HAL impls (/vendor/lib64/hw) ==="
ls $W/mnt/lib64/hw 2>/dev/null | head -80 | tr '\n' ' '
echo
echo "=== vial HAL impl count ==="
ls $W/mnt/lib64/hw 2>/dev/null | wc -l
echo "=== vivo vendor build.prop (key lines) ==="
grep -E '^(ro\.(build|product|vivo|vendor\.vndk|vndk|treble|board|hardware)|ro\.vivo\.)' $W/mnt/build.prop 2>/dev/null | head -60
echo "=== vivo vendor etc/init (list) ==="
ls $W/mnt/etc/init/ 2>/dev/null | head -60 | tr '\n' ' '
echo
echo "=== vivo vendor size by top dir ==="
du -sk $W/mnt/* 2>/dev/null | sort -n -r | head -15
umount $W/mnt
echo DONE
