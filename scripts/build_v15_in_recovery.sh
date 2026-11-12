#!/system/bin/sh
# v15: v14 system + append forced adbd/gadget triggers into init.usb.rc (guaranteed parsed)
B=/data/local/tmp/v15
mkdir -p $B/mnt
mount -t erofs -o ro $B/vivo_system_v14.img $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null
RC=$B/tree/system/etc/init/hw/init.usb.rc
cat >> $RC <<'EOF'

# ===== OriginOS port: force adb (TCP + USB gadget) and run fixup scripts =====
on late-init
    setprop service.adb.tcp.port 5555
    start adbd

# vendor sets vendor.usb.controller in its 'on boot'; after that force standard gadget config
on property:vendor.usb.controller=*
    setprop sys.usb.config mtp,adb

service portfix_early /system/bin/sh /system/etc/portfix_early.sh
    class core
    user root
    group root
    oneshot
    disabled

service portfix_boot /system/bin/sh /system/etc/portfix_boot.sh
    class core
    user root
    group root
    oneshot
    disabled

on post-fs-data
    start portfix_early

on property:sys.boot_completed=1
    start portfix_boot
EOF
echo "--- appended rc tail ---"
tail -32 $RC
cp -f $B/portfix_early.sh $B/tree/system/etc/portfix_early.sh 2>/dev/null
cp -f $B/portfix_boot.sh $B/tree/system/etc/portfix_boot.sh 2>/dev/null
chmod 755 $B/tree/system/etc/portfix_early.sh $B/tree/system/etc/portfix_boot.sh 2>/dev/null
rm -f $B/vivo_system_v15.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v15.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v15.img
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v15.img $B/ver && { grep -c 'OriginOS port' $B/ver/system/etc/init/hw/init.usb.rc; grep -E '^persist.sys.usb.config=' $B/ver/system/build.prop; umount $B/ver; }
echo DONE
