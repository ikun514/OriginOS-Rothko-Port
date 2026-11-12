#!/system/bin/sh
echo "===== check zram in flashed vendor ====="
mkdir -p /mnt/v
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/v 2>&1; echo "mount rc=$?"
grep -rl 'zram' /mnt/v/etc/init /mnt/v/bin /mnt/v/etc 2>/dev/null | head -10
echo "--- zram rc content (if any) ---"
for f in $(grep -rl 'zram' /mnt/v/etc/init 2>/dev/null | head -3); do echo "== $f"; head -40 "$f"; done
echo "--- vendor props mentioning zram ---"
grep -iE 'zram' /mnt/v/build.prop /mnt/v/etc/build.prop 2>/dev/null | head -10
umount /mnt/v 2>/dev/null
echo "===== check zram in odm ====="
mkdir -p /mnt/o
mount -t erofs -o ro /dev/block/mapper/odm_a /mnt/o 2>&1; echo "mount rc=$?"
grep -rl 'zram' /mnt/o/etc/init 2>/dev/null | head -5
umount /mnt/o 2>/dev/null
echo "===== check zram in system (vivo) ====="
mkdir -p /mnt/s
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>&1; echo "mount rc=$?"
grep -rl 'zram' /mnt/s/system/etc/init /mnt/s/system/bin 2>/dev/null | head -10
for f in $(grep -rl 'zram' /mnt/s/system/etc/init 2>/dev/null | head -3); do echo "== $f"; head -50 "$f"; done
umount /mnt/s 2>/dev/null
echo "===== current kernel zram module? ====="
ls /sys/module/zram 2>&1
ls /sys/block/ 2>/dev/null | head -20
echo DONE
