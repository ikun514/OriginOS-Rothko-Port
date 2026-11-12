#!/system/bin/sh
# v22 = v21 + force USB composition: vivo framework sets sys.usb.config=charging,adb
#        → remap to mtp,adb so vivo's own configfs triggers bind gadget (MTP+adb)
B=/data/local/tmp/v22
mkdir -p $B
SRC=/data/local/tmp/v22/base_v21.img
[ -f "$SRC" ] || { echo "NO BASE"; exit 1; }
mkdir -p $B/mnt
mount -t erofs -o ro $SRC $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== build.prop: usb props ==="
SBP=$B/tree/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "persist.sys.usb.config=mtp,adb"
add_prop "ro.sys.usb.charging.only=no"
add_prop "ro.sys.usb.storage.type=mtp"
add_prop "ro.adb.secure=0"
add_prop "ro.debuggable=1"
add_prop "service.adb.tcp.port=5555"
grep -E '^(persist.sys.usb.config|ro.sys.usb.charging.only|ro.adb.secure)=' $SBP

echo "=== init.usb.rc: remap charging modes to mtp,adb ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
grep -q 'OriginOS port: remap charging' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: remap charging modes to mtp,adb so gadget binds (vivo framework sets charging,adb) =====
on property:sys.usb.config=charging,adb
    setprop sys.usb.config mtp,adb

on property:sys.usb.config=charging
    setprop sys.usb.config mtp,adb

on property:sys.usb.config=none && property:sys.boot_completed=1
    setprop sys.usb.config mtp,adb
EOF
tail -14 $RC

echo "=== repack ==="
rm -f $B/vivo_system_v22.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v22.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v22.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v22.img $B/ver && {
  grep -E '^(persist.sys.usb.config|ro.sys.usb.charging.only)=' $B/ver/system/build.prop
  grep -c 'remap charging' $B/ver/system/etc/init/hw/init.usb.rc
  umount $B/ver
}
echo DONE
