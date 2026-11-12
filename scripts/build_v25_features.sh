#!/system/bin/sh
# v25 = v24 changes (rothko usb rc + adb-only USB + permissive) + real model props + boot automation
# Builds from /data/local/tmp/v24/base_v23.img (v23 system image)
B=/data/local/tmp/v25
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

echo "=== usb: mtp,adb -> adb (adb-only composition that worked in v24) ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
sed -i 's|setprop sys.usb.config mtp,adb|setprop sys.usb.config adb|g' $RC
grep -c 'setprop sys.usb.config adb' $RC

echo "=== build.prop: real model props ==="
SBP=$B/tree/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "ro.vivo.internet.name=Redmi K70 Ultra"
add_prop "ro.vivo.market.name=Redmi K70 Ultra"
add_prop "persist.sys.usb.config=adb"
add_prop "ro.adb.secure=0"
add_prop "ro.debuggable=1"
add_prop "service.adb.tcp.port=5555"
grep -E '^(ro.vivo.(internet|market).name|persist.sys.usb.config|ro.adb.secure)=' $SBP

echo "=== boot automation service (auto USB debug + skip OOBE) ==="
cp -f $B/portfix_boot.sh $B/tree/system/etc/portfix_boot.sh
chmod 755 $B/tree/system/etc/portfix_boot.sh
grep -q 'portfix_boot' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: boot automation (auto USB debug + skip OOBE) =====
service portfix_boot /system/bin/sh /system/etc/portfix_boot.sh
    class late_start
    user root
    group root
    oneshot
    disabled
    seclabel u:r:su:s0

on property:sys.boot_completed=1
    start portfix_boot
EOF
tail -14 $RC

echo "=== repack ==="
rm -f $B/vivo_system_v25.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v25.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v25.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v25.img $B/ver && {
  grep -E '^ro.vivo.(internet|market).name=' $B/ver/system/build.prop
  grep -c 'portfix_boot' $B/ver/system/etc/init/hw/init.usb.rc
  ls -l $B/ver/system/etc/portfix_boot.sh
  umount $B/ver
}
echo DONE
