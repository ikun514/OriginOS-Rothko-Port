#!/system/bin/sh
W=/data/local/tmp/work
mount -t erofs -o ro $W/images/system.img $W/mnt 2>/dev/null || { chcon u:object_r:system_file:s0 $W/images/system.img; mount -t erofs -o ro $W/images/system.img $W/mnt; }
echo "rc=$?"
echo "=== root of vivo system image ==="
ls -la $W/mnt | head -45
echo "=== /mnt/system ==="
ls -la $W/mnt/system | head -40
echo "=== /mnt/system/build.prop head ==="
head -20 $W/mnt/system/build.prop 2>/dev/null
echo "=== /mnt/init.vivo.rc ==="
cat $W/mnt/init.vivo.rc 2>/dev/null | head -30
echo "=== /mnt/system/etc/init/hw/init.rc exists? ==="
ls -l $W/mnt/system/etc/init/hw/init.rc $W/mnt/system/bin/init $W/mnt/init 2>/dev/null
echo "=== du /mnt/system top dirs ==="
du -sk $W/mnt/system/* 2>/dev/null | sort -n -r | head -20
echo "=== apks in system ==="
find $W/mnt/system -name '*.apk' -printf '%s %p\n' 2>/dev/null | sort -n -r | head -20
echo "=== apk total ==="
find $W/mnt/system -name '*.apk' 2>/dev/null | wc -l
du -sk $W/mnt/system/app $W/mnt/system/priv-app $W/mnt/system/apex $W/mnt/system/lib64 $W/mnt/system/framework $W/mnt/system/fonts $W/mnt/system/media 2>/dev/null
umount $W/mnt
echo DONE
