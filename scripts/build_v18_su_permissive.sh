#!/system/bin/sh
# v18: v12 system (v11 image) + image-level permissive via su domain (su is typepermissive in vivo debug policy)
B=/data/local/tmp/v18
mkdir -p $B
echo "=== mount base v11 ==="
mkdir -p $B/mnt
mount -t erofs -o ro $B/base_sys_v11.img $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== append permissive exec to vivo init.usb.rc (definitely parsed) ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
grep -q 'OriginOS port: image-level permissive' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: image-level permissive via su domain =====
# vivodebug policy marks su as typepermissive; exec into su domain from init works
# (same pattern as /system/etc/init/simpleperf.rc). init domain itself may not exec shell.
on post-fs-data
    exec u:r:su:s0 root root -- /system/bin/sh /system/etc/portfix_perm.sh
EOF
tail -8 $RC
cp -f $B/portfix_perm.sh $B/tree/system/etc/portfix_perm.sh
chown 0:0 $B/tree/system/etc/portfix_perm.sh 2>/dev/null
chmod 755 $B/tree/system/etc/portfix_perm.sh
echo "=== repack ==="
rm -f $B/vivo_system_v18.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v18.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v18.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v18.img $B/ver && { grep -c 'portfix_perm' $B/ver/system/etc/init/hw/init.usb.rc; ls -Z $B/ver/system/etc/portfix_perm.sh; umount $B/ver; }
echo DONE
