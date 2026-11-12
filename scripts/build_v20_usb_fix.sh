#!/system/bin/sh
# v20 = v19 (minimal permissive) + persist.sys.usb.config=mtp,adb  (vivo rc triggers only know "mtp,adb", not "adb,mtp")
B=/data/local/tmp/v20
mkdir -p $B
echo "=== mount base ==="
mkdir -p $B/mnt
mount -t erofs -o ro /data/local/tmp/v19/base_sys_v11.img $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== CIL allow rules ==="
CIL=$B/tree/system/etc/selinux/plat_sepolicy.cil
grep -q 'OriginOS port: allow init to setenforce' $CIL || cat >> $CIL <<'EOF'

;; OriginOS port: allow init domain to switch SELinux to permissive (image-level, no module)
(allow init kernel (security (setenforce)))
(allow init selinuxfs (file (open read write getattr)))
EOF

echo "=== init.usb.rc early-init permissive ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
grep -q 'OriginOS port: permissive' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: image-level permissive =====
on early-init
    write /sys/fs/selinux/enforce 0
EOF

echo "=== build.prop usb config (order matters for vivo rc triggers) ==="
SBP=$B/tree/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "persist.sys.usb.config=mtp,adb"
add_prop "ro.adb.secure=0"
add_prop "ro.debuggable=1"
add_prop "service.adb.tcp.port=5555"
grep -E '^(persist.sys.usb.config|ro.adb.secure|ro.debuggable|service.adb.tcp.port)=' $SBP

echo "=== repack ==="
rm -f $B/vivo_system_v20.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v20.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v20.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v20.img $B/ver && {
  grep -E '^persist.sys.usb.config=' $B/ver/system/build.prop
  grep -c 'selinux/enforce' $B/ver/system/etc/init/hw/init.usb.rc
  grep -c 'allow init kernel' $B/ver/system/etc/selinux/plat_sepolicy.cil
  umount $B/ver
}
echo DONE
