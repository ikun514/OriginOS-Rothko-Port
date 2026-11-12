#!/system/bin/sh
echo "===== PStore ====="
ls -la /sys/fs/pstore/ 2>&1
echo "===== console-ramoops strings (filtered) ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'init:|erofs|Failed|panic|system_server|zygote|vold|avb|odm|FATAL|Watchdog|mount' | tail -80
echo "===== dmesg (recovery boot) tail ====="
dmesg 2>/dev/null | tail -30
echo "===== AEE / crash dirs ====="
for d in /data/aee_exp /data/vendor/aee /data/vendor/mtklog /cache/recovery /metadata; do echo "-- $d"; ls -la $d 2>/dev/null | head -8; done
echo "===== flashed odm vs original odm ====="
mkdir -p /mnt/odmflash /mnt/odmorig
mount -t erofs -o ro /dev/block/mapper/odm_a /mnt/odmflash 2>&1; echo "flash mount rc=$?"
mount -t erofs -o ro /data/local/tmp/build/rothko_odm_orig.img /mnt/odmorig 2>&1; echo "orig mount rc=$?"
echo "flash files: $(find /mnt/odmflash -type f 2>/dev/null | wc -l)"
echo "orig  files: $(find /mnt/odmorig -type f 2>/dev/null | wc -l)"
echo "--- build.prop diff (orig vs flash) ---"
diff /mnt/odmorig/etc/build.prop /mnt/odmflash/etc/build.prop 2>/dev/null | head -20
echo "--- label samples flash ---"
ls -Z /mnt/odmflash/etc/build.prop /mnt/odmflash/bin/hw 2>/dev/null | head -4
echo "--- label samples orig ---"
ls -Z /mnt/odmorig/etc/build.prop /mnt/odmorig/bin/hw 2>/dev/null | head -4
echo "--- size compare ---"
du -sb /mnt/odmflash /mnt/odmorig 2>/dev/null
umount /mnt/odmflash 2>/dev/null; umount /mnt/odmorig 2>/dev/null
echo "===== misc / boot mode info ====="
cat /proc/cmdline 2>/dev/null | tr ' ' '\n' | grep -iE 'boot|slot|mode|reason' | head -20
echo DONE
