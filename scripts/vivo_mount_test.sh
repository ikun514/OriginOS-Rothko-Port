#!/system/bin/sh
set -x
W=/data/local/tmp/work
mkdir -p $W/images $W/mnt
cp -f /sdcard/work/images/product.img $W/images/ 2>/dev/null
cp -f /sdcard/work/images/odm.img $W/images/ 2>/dev/null
cp -f /sdcard/work/images/system_ext.img $W/images/ 2>/dev/null
chcon u:object_r:system_file:s0 $W/images/*.img
echo "=== dump.erofs product ==="
dump.erofs -s $W/images/product.img 2>&1 | head -40
echo "=== mount vivo product on rothko kernel ==="
mount -t erofs -o ro $W/images/product.img $W/mnt
echo "mount rc=$?"
mount | grep "$W/mnt"
echo "=== product top-level ==="
ls -la $W/mnt | head -30
du -sk $W/mnt/* 2>/dev/null | sort -n -r | head -20
umount $W/mnt
echo "=== odm top ==="
mount -t erofs -o ro $W/images/odm.img $W/mnt && ls -la $W/mnt && du -sk $W/mnt/* | sort -n -r | head -20 && umount $W/mnt
echo "=== system_ext top ==="
mount -t erofs -o ro $W/images/system_ext.img $W/mnt && ls $W/mnt && du -sk $W/mnt/* | sort -n -r | head -20 && umount $W/mnt
echo DONE
