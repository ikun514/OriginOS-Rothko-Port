#!/system/bin/sh
B=/data/local/tmp
echo "=== original odm root/apex ==="
mkdir -p /mnt/oo
mount -t erofs -o ro $B/orig_odm.img /mnt/oo 2>&1; echo "mount rc=$?"
stat -c 'ROOT: %C %A %U:%G' /mnt/oo 2>&1
ls -ldZ /mnt/oo/apex 2>&1 || echo "no /apex in odm"
ls /mnt/oo 2>&1
umount /mnt/oo 2>/dev/null
echo "=== system root label (for reference) ==="
mkdir -p /mnt/sv
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/sv 2>&1 >/dev/null
stat -c 'SYSTEM ROOT: %C' /mnt/sv 2>&1
umount /mnt/sv 2>/dev/null
echo "=== vendor root label (for reference) ==="
mkdir -p /mnt/vv
mount -t erofs -o ro /dev/block/mapper/vendor_a /mnt/vv 2>&1 >/dev/null
stat -c 'VENDOR ROOT: %C' /mnt/vv 2>&1
umount /mnt/vv 2>/dev/null
echo DONE
