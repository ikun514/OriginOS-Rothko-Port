#!/system/bin/sh
# v19: v12 system (v11 image) + minimal image-level permissive:
#   1) plat_sepolicy.cil: two allow rules so init domain may turn SELinux permissive
#   2) vivo init.usb.rc: write /sys/fs/selinux/enforce 0 at early-init
B=/data/local/tmp/v19
mkdir -p $B
echo "=== mount base v11 ==="
mkdir -p $B/mnt
mount -t erofs -o ro $B/base_sys_v11.img $B/mnt || { echo "MOUNT FAIL"; exit 1; }
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== patch plat_sepolicy.cil (2 allow rules) ==="
CIL=$B/tree/system/etc/selinux/plat_sepolicy.cil
if ! grep -q 'OriginOS port: allow init to setenforce' $CIL; then
cat >> $CIL <<'EOF'

;; OriginOS port: allow init domain to switch SELinux to permissive (image-level, no module)
(allow init kernel (security (setenforce)))
(allow init selinuxfs (file (open read write getattr)))
EOF
fi
tail -4 $CIL

echo "=== patch vivo init.usb.rc (early-init write enforce 0) ==="
RC=$B/tree/system/etc/init/hw/init.usb.rc
if ! grep -q 'OriginOS port: permissive' $RC; then
cat >> $RC <<'EOF'

# ===== OriginOS port: image-level permissive =====
on early-init
    write /sys/fs/selinux/enforce 0
EOF
fi
tail -5 $RC

echo "=== repack ==="
rm -f $B/vivo_system_v19.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v19.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_system_v19.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v19.img $B/ver && {
  grep -c 'allow init kernel' $B/ver/system/etc/selinux/plat_sepolicy.cil
  grep -c 'selinux/enforce' $B/ver/system/etc/init/hw/init.usb.rc
  umount $B/ver
}
echo DONE
