#!/system/bin/sh
# v21 = v20 + init-service diagnostic dump (works without adb: writes /data/portfix_diag/diag.txt)
B=/data/local/tmp/v21
mkdir -p $B
SRC=/data/local/tmp/v21/base_v20.img
[ -f "$SRC" ] || { echo "NO BASE"; exit 1; }
echo "src=$SRC"
mkdir -p $B/mnt
mount -t erofs -o ro $SRC $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== add diag script ==="
cp -f $B/portfix_diag.sh $B/tree/system/etc/portfix_diag.sh
chmod 755 $B/tree/system/etc/portfix_diag.sh

echo "=== append diag service to init.usb.rc ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
grep -q 'portfix_diag' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: diagnostics dump (no adb needed) =====
service portfix_diag /system/bin/sh /system/etc/portfix_diag.sh
    class late_start
    user root
    group root
    oneshot
    disabled
    seclabel u:r:su:s0

on property:sys.boot_completed=1
    start portfix_diag
EOF
tail -12 $RC

echo "=== repack ==="
rm -f $B/vivo_system_v21.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v21.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v21.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v21.img $B/ver && {
  grep -c 'portfix_diag' $B/ver/system/etc/init/hw/init.usb.rc
  ls -l $B/ver/system/etc/portfix_diag.sh
  grep -E '^persist.sys.usb.config=' $B/ver/system/build.prop
  umount $B/ver
}
echo DONE

