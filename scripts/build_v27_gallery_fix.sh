#!/system/bin/sh
# v27 = current flashed system (v25) + remove /system/app/Vivo3rdAlgoService (gallery fix per user)
B=/data/local/tmp/v27
mkdir -p $B/mnt
echo "=== mount flashed system_a ==="
mount -t erofs -o ro /dev/block/mapper/system_a $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
echo "=== copy tree ==="
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null
echo "=== remove Vivo3rdAlgoService ==="
ls -ld $B/tree/system/app/Vivo3rdAlgoService 2>/dev/null
rm -rf $B/tree/system/app/Vivo3rdAlgoService
ls -ld $B/tree/system/app/Vivo3rdAlgoService 2>/dev/null || echo "removed"
# also drop its oat/lib leftovers if any
rm -rf $B/tree/system/app/Vivo3rdAlgoService
echo "=== repack ==="
rm -f $B/vivo_system_v27.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v27.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v27.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v27.img $B/ver && {
  ls -d $B/ver/system/app/Vivo3rdAlgoService 2>/dev/null || echo "no Vivo3rdAlgoService OK"
  grep -E '^ro.vivo.(internet|market).name=' $B/ver/system/build.prop
  grep -c 'portfix_boot' $B/ver/system/etc/init/hw/init.usb.rc
  umount $B/ver
}
echo DONE
