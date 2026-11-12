#!/system/bin/sh
echo "===== tombstones: process/abort ====="
for f in /data/tombstones/tombstone_0?; do
  [ -f "$f" ] || continue
  echo "--- $(basename $f)"
  awk '/^(Cmdline|pid|signal|Abort message):/ {print} /^backtrace:/{print; c=4; next} c>0 {print; c--}' "$f" 2>/dev/null | head -12
done
echo
echo "===== system usb related binaries (flashed system_a) ====="
mkdir -p /mnt/s
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>/dev/null; echo "mount rc=$?"
ls -lZ /mnt/s/system/bin/vusbd 2>/dev/null
ls /mnt/s/system/bin/hw 2>/dev/null | grep -iE 'usb|vivo' | head -20
ls /mnt/s/system/lib64 2>/dev/null | grep -iE 'vivo.*usb|usb.*vivo' | head -10
echo "--- vivo usbd.rc ---"
cat /mnt/s/system/etc/init/usbd.rc 2>/dev/null | head -60
echo "--- vusbd references in init rc ---"
grep -rn 'vusbd' /mnt/s/system/etc/init 2>/dev/null | head -10
echo
echo "===== vendor usb HAL (flashed vendor_a) ====="
mkdir -p /mnt/v
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/v 2>/dev/null; echo "mount rc=$?"
ls /mnt/v/bin/hw 2>/dev/null | grep -iE 'usb|gadget'
grep -rn 'vusbd\|vendor.vivo.hardware.usb' /mnt/v/etc/init 2>/dev/null | head -10
echo "--- vendor rc usb service ---"
grep -rn 'usb' /mnt/v/etc/init/hw/init.mt6989.usb.rc 2>/dev/null | head -30
umount /mnt/s 2>/dev/null; umount /mnt/v 2>/dev/null
echo DONE
