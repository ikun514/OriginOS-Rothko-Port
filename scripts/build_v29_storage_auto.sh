#!/system/bin/sh
# v29 = v28 (flashed) + portfix_boot.sh gains external-storage auto-mount workaround
B=/data/local/tmp/v29
mkdir -p $B
mkdir -p $B/mnt
mount -t erofs -o ro /dev/block/mapper/system_a $B/mnt || { echo "SYS MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null
echo "=== replace portfix_boot.sh ==="
cp -f $B/portfix_boot.sh $B/tree/system/etc/portfix_boot.sh
chmod 755 $B/tree/system/etc/portfix_boot.sh
head -6 $B/tree/system/etc/portfix_boot.sh
echo "=== repack ==="
rm -f $B/vivo_system_v29.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v29.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v29.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v29.img $B/ver && {
  grep -c "sm mount" $B/ver/system/etc/portfix_boot.sh
  grep -c 'portfix_boot' $B/ver/system/etc/init/hw/init.usb.rc
  umount $B/ver
}
echo DONE
