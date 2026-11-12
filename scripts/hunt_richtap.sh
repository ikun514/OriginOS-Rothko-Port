#!/system/bin/sh
W=/data/local/tmp/work
ls -l $W/images/vendor.img 2>/dev/null || echo "vendor.img missing"
mkdir -p $W/mntv
chcon u:object_r:system_file:s0 $W/images/vendor.img 2>/dev/null
mount -t erofs -o ro $W/images/vendor.img $W/mntv 2>/dev/null || { chcon u:object_r:system_file:s0 $W/images/vendor.img; mount -t erofs -o ro $W/images/vendor.img $W/mntv; }
echo "mount rc=$?"
echo "=== vendor/bin/hw ==="
ls $W/mntv/bin/hw 2>/dev/null | head -60
echo "=== search richtap in vendor ==="
grep -rl -i "richtap" $W/mntv/lib64 $W/mntv/bin $W/mntv/etc 2>/dev/null | head -20
echo "=== search aac in vendor ==="
grep -rl -i "vendor.aac" $W/mntv/lib64 $W/mntv/bin $W/mntv/etc 2>/dev/null | head -20
echo "=== vivo vibrator related ==="
ls $W/mntv/lib64/hw 2>/dev/null | grep -i -E "vibr|richtap|aac"
ls $W/mntv/bin/hw 2>/dev/null | grep -i -E "vibr|richtap|aac"
echo "=== vintf manifest mentioning vibrator ==="
grep -l -i "vibrator" $W/mntv/etc/vintf/manifest/*.xml 2>/dev/null
umount $W/mntv
echo DONE
