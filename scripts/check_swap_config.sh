#!/system/bin/sh
mkdir -p /mnt/v
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/v 2>/dev/null
echo "===== fstab.enableswap ====="
cat /mnt/v/etc/fstab.enableswap 2>/dev/null
echo
echo "===== init.mt6989.rc: swap/zram context ====="
grep -n -i -B3 -A12 -E 'zram|swap' /mnt/v/etc/init/hw/init.mt6989.rc 2>/dev/null | head -120
echo "===== other vendor rc files with swap ====="
grep -rln -iE 'zram|swapon|mkswap' /mnt/v/etc/init 2>/dev/null
echo "===== vendor fstab.mt6989 swap/zram lines ====="
grep -n -iE 'zram|swap' /mnt/v/etc/fstab.mt6989 2>/dev/null
echo "===== vivo system init.rc: zram/swap ====="
mkdir -p /mnt/s
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>/dev/null
grep -n -i -B2 -A10 -E 'zram|swapon|mkswap' /mnt/s/system/etc/init/hw/init.rc 2>/dev/null | head -80
echo "===== vivo system etc/init files mentioning swap ====="
grep -rln -iE 'zram|swapon|mkswap' /mnt/s/system/etc/init 2>/dev/null | head -10
umount /mnt/v 2>/dev/null; umount /mnt/s 2>/dev/null
echo DONE
