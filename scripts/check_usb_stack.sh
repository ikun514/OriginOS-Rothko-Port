#!/system/bin/sh
echo "===== system init.usb.rc (vivo) ====="
mkdir -p /mnt/s
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>/dev/null
grep -nE "service|usb|gadget" /mnt/s/system/etc/init/hw/init.usb.rc 2>/dev/null | head -40
echo "===== vivo usb related rc in system/etc/init ====="
grep -rln -iE 'usb' /mnt/s/system/etc/init 2>/dev/null | head -10
echo "===== vivo vendor usb services ====="
mkdir -p /mnt/v
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/v 2>/dev/null
ls /mnt/v/bin/hw 2>/dev/null | grep -iE 'usb|gadget' 
echo "--- init.mt6989.usb.rc ---"
grep -nE "service|on |setprop|write /config" /mnt/v/etc/init/hw/init.mt6989.usb.rc 2>/dev/null | head -40
echo "===== vivo odm usb rc ====="
mkdir -p /mnt/o
mount -t erofs -o ro /dev/block/mapper/odm_a /mnt/o 2>/dev/null
grep -rln -iE 'usb' /mnt/o/etc/init 2>/dev/null | head -10
echo "===== vivo system hal list for usb (files) ====="
ls /mnt/s/system/etc/vintf 2>/dev/null
grep -iE 'usb|gadget' /mnt/s/system/etc/vintf/manifest.xml 2>/dev/null | head -10
echo "===== vendor vintf usb ====="
grep -iE 'usb|gadget' /mnt/v/etc/vintf/manifest.xml 2>/dev/null | head -10
umount /mnt/s /mnt/v /mnt/o 2>/dev/null
echo DONE
