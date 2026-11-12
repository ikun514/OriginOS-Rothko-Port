#!/system/bin/sh
echo "===== rothko original /system/etc/init/hw: usb* ====="
mkdir -p /mnt/r /mnt/v
mount -t erofs -o ro /data/local/tmp/v23/rothko_system.img /mnt/r 2>/dev/null; echo "rothko mount rc=$?"
ls -l /mnt/r/system/etc/init/hw/ 2>/dev/null | grep -iE 'usb'
echo "--- all files ---"
ls /mnt/r/system/etc/init/hw/ 2>/dev/null
echo
echo "===== vivo (ported) /system/etc/init/hw ====="
mount -t erofs -o ro /data/local/tmp/v21/vivo_system_v21.img /mnt/v 2>/dev/null; echo "vivo mount rc=$?"
ls -l /mnt/v/system/etc/init/hw/ 2>/dev/null | grep -iE 'usb'
echo "--- all files ---"
ls /mnt/v/system/etc/init/hw/ 2>/dev/null
echo
echo "===== hashes of candidate usb* files ====="
for f in /mnt/r/system/etc/init/hw/*usb*; do [ -f "$f" ] && sha256sum "$f"; done
for f in /mnt/v/system/etc/init/hw/*usb*; do [ -f "$f" ] && sha256sum "$f"; done
umount /mnt/r /mnt/v 2>/dev/null
echo DONE
