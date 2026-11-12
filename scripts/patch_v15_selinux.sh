#!/system/bin/sh
# v15b: in-place patch already-extracted tree (fast):
#  1) early-init: write /sys/fs/selinux/enforce 0   (== KSU module 的 setenforce 0，但做进镜像、清数据也不丢)
#  2) force adbd (tcp 5555) + gadget mtp,adb
#  3) run fixup scripts
B=/data/local/tmp/v15
T=$B/tree
[ -d "$T/system" ] || { echo "NO TREE"; exit 1; }
RC=$T/system/etc/init/hw/init.usb.rc
if ! grep -q 'OriginOS port' $RC; then
cat >> $RC <<'EOF'

# ===== OriginOS port: force permissive + adb (TCP + USB gadget) + fixup scripts =====
on early-init
    write /sys/fs/selinux/enforce 0

on late-init
    setprop service.adb.tcp.port 5555
    start adbd

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
else
  echo "rc already has port block"
  grep -q 'selinux/enforce' $RC || sed -i 's|^on early-init$|on early-init\n    write /sys/fs/selinux/enforce 0|' $RC
fi
echo "--- rc head ---"
head -20 $RC
echo "--- portfix block ---"
grep -n -A3 'OriginOS port' $RC | head -10
echo "--- build.prop check ---"
grep -E '^(persist.sys.usb.config|service.adb.tcp.port|ro.adb.secure|ro.debuggable)=' $T/system/build.prop
rm -f $B/vivo_system_v15.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v15.img $T 2>&1 | tail -2
ls -l $B/vivo_system_v15.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v15.img $B/ver && { grep -c 'selinux/enforce' $B/ver/system/etc/init/hw/init.usb.rc; grep -c 'start adbd' $B/ver/system/etc/init/hw/init.usb.rc; umount $B/ver; }
echo DONE
