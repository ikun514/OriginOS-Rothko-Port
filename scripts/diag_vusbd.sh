#!/system/bin/sh
echo "===== vivo init.usb.rc: sys.usb.config triggers ====="
mkdir -p /mnt/s /mnt/v
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>/dev/null
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/v 2>/dev/null
grep -n 'sys.usb.config' /mnt/s/system/etc/init/hw/init.usb.rc | head -40
echo
echo "===== vivo init.usb.configfs.rc: triggers/actions ====="
grep -nE 'on |setprop sys.usb|write /config|start |stop ' /mnt/s/system/etc/init/hw/init.usb.configfs.rc | head -60
echo
echo "===== usbd.rc full ====="
cat /mnt/s/system/etc/init/usbd.rc 2>/dev/null
echo
echo "===== vusbd strings: paths/props it uses ====="
strings /mnt/s/system/bin/vusbd 2>/dev/null | grep -E '^/(vendor|system|sys|dev|config|data)[A-Za-z0-9_./-]*$' | sort -u | head -40
echo "--- props ---"
strings /mnt/s/system/bin/vusbd 2>/dev/null | grep -E '^(persist|sys|ro|vendor)\.' | sort -u | head -40
echo
echo "===== vivo vendor usb related files (all) ====="
ls /mnt/v/etc | grep -iE 'usb|vivo' | head -20
find /mnt/v -maxdepth 3 -iname '*usb*' 2>/dev/null | head -20
umount /mnt/s /mnt/v 2>/dev/null
echo DONE
