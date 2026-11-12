#!/system/bin/sh
# v14: v13 system + fix usb config order (mtp,adb) ; keep everything else
B=/data/local/tmp/v14
mkdir -p $B/mnt
echo "=== mount v13 system ==="
mount -t erofs -o ro $B/vivo_system_v13.img $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null
SBP=$B/tree/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "persist.sys.usb.config=mtp,adb"
add_prop "service.adb.tcp.port=5555"
add_prop "persist.adb.tcp.port=5555"
add_prop "ro.adb.secure=0"
add_prop "ro.debuggable=1"
grep -E '^(persist.sys.usb.config|service.adb.tcp.port|persist.adb.tcp.port|ro.adb.secure)=' $SBP
echo "=== fix portfix scripts ==="
cp -f $B/portfix.rc $B/tree/system/etc/init/portfix.rc 2>/dev/null
cp -f $B/portfix_early.sh $B/tree/system/etc/portfix_early.sh 2>/dev/null
cp -f $B/portfix_boot.sh $B/tree/system/etc/portfix_boot.sh 2>/dev/null
chmod 644 $B/tree/system/etc/init/portfix.rc 2>/dev/null
chmod 755 $B/tree/system/etc/portfix_early.sh $B/tree/system/etc/portfix_boot.sh 2>/dev/null
rm -f $B/vivo_system_v14.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v14.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v14.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v14.img $B/ver && { grep -E '^(persist.sys.usb.config|service.adb.tcp.port)=' $B/ver/system/build.prop; umount $B/ver; }
echo DONE
