#!/system/bin/sh
# v24 = v23 (rothko usb rc replaced + permissive) with USB composition forced to adb-only.
# Reason (from v23 diag): framework sets sys.usb.config=charging,adb; remapping to mtp,adb requires
# vendor.usb.ffs.mtp.ready=1 (MTP daemon) which never becomes ready -> UDC never bound -> timeout.
# "adb" only needs sys.usb.ffs.ready (set by adbd) -> gadget binds -> USB enumerates.
B=/data/local/tmp/v24
mkdir -p $B
SRC=/data/local/tmp/v24/base_v23.img
[ -f "$SRC" ] || { echo "NO BASE"; exit 1; }
mkdir -p $B/mnt
mount -t erofs -o ro $SRC $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

RC=$B/tree/system/etc/init/hw/init.usb.rc
echo "=== before: our appended remap lines ==="
grep -n 'setprop sys.usb.config mtp,adb' $RC | head -5
# change remap target mtp,adb -> adb (only in our appended block)
sed -i 's|setprop sys.usb.config mtp,adb|setprop sys.usb.config adb|g' $RC
echo "=== after ==="
grep -n 'setprop sys.usb.config adb' $RC | head -8

echo "=== append: force adb-only composition at boot ==="
grep -q 'OriginOS port: force adb-only' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: force adb-only composition =====
on property:sys.boot_completed=1
    setprop sys.usb.config adb
EOF
tail -8 $RC

echo "=== repack ==="
rm -f $B/vivo_system_v24.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v24.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v24.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v24.img $B/ver && {
  grep -n -A2 'remap charging' $B/ver/system/etc/init/hw/init.usb.rc | head -8
  umount $B/ver
}
echo DONE
