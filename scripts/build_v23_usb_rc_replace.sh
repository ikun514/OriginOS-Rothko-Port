#!/system/bin/sh
# v23 = v21 base (permissive) but with rothko's original init.usb.rc + init.usb.configfs.rc
#       (user request). Re-append permissive early-init block, diag service and adb helpers.
B=/data/local/tmp/v23
mkdir -p $B
SRC=/data/local/tmp/v21/vivo_system_v21.img
[ -f "$SRC" ] || { echo "NO BASE"; exit 1; }
echo "=== mount base ==="
mkdir -p $B/mnt
mount -t erofs -o ro $SRC $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== mount rothko original system, copy its usb rc files ==="
mkdir -p $B/mntr
mount -t erofs -o ro $B/rothko_system.img $B/mntr || { echo "ROTHKO MOUNT FAIL"; exit 1; }
ls -l $B/mntr/system/etc/init/hw/init.usb.rc $B/mntr/system/etc/init/hw/init.usb.configfs.rc
cp -f $B/mntr/system/etc/init/hw/init.usb.rc $B/tree/system/etc/init/hw/init.usb.rc
cp -f $B/mntr/system/etc/init/hw/init.usb.configfs.rc $B/tree/system/etc/init/hw/init.usb.configfs.rc
chmod 644 $B/tree/system/etc/init/hw/init.usb.rc $B/tree/system/etc/init/hw/init.usb.configfs.rc
echo "--- replaced files (rothko) ---"
grep -c 'service adbd' $B/tree/system/etc/init/hw/init.usb.rc
grep -n 'sys.usb.config=mtp,adb' $B/tree/system/etc/init/hw/init.usb.configfs.rc | head -3
umount $B/mntr 2>/dev/null

echo "=== re-append permissive + diag + adb helpers to init.usb.rc ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
cat >> $RC <<'EOF'

# ===== OriginOS port: image-level permissive + adb helpers (kept after rothko usb rc replacement) =====
on early-init
    write /sys/fs/selinux/enforce 0

on property:sys.usb.config=charging,adb
    setprop sys.usb.config mtp,adb

on property:sys.usb.config=charging
    setprop sys.usb.config mtp,adb

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
tail -20 $RC

echo "=== keep plat CIL allows (from v21 base) ==="
grep -c 'allow init kernel' $B/tree/system/etc/selinux/plat_sepolicy.cil

echo "=== repack ==="
rm -f $B/vivo_system_v23.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v23.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v23.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v23.img $B/ver && {
  grep -c 'service adbd' $B/ver/system/etc/init/hw/init.usb.rc
  grep -c 'selinux/enforce' $B/ver/system/etc/init/hw/init.usb.rc
  grep -c 'portfix_diag' $B/ver/system/etc/init/hw/init.usb.rc
  grep -c 'mtp,adb' $B/ver/system/etc/init/hw/init.usb.configfs.rc
  umount $B/ver
}
echo DONE
