#!/system/bin/sh
# v17: permissive at SELinux policy level, split per partition to avoid undefined-type compile errors.
#  A) system: append (typepermissive T) to plat_sepolicy.cil for types declared in system CILs
#  B) vendor: rebuild vendor image with (typepermissive T) in vendor_sepolicy.cil (labels preserved)
B=/data/local/tmp/v17
mkdir -p $B
echo "############ A. system v17 ############"
mkdir -p $B/mnts
mount -t erofs -o ro $B/base_sys_v15.img $B/mnts || { echo "SYS MOUNT FAIL"; exit 1; }
cp -f $B/mnts/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree_sys; mkdir -p $B/tree_sys
cp -a $B/mnts/. $B/tree_sys/ 2>/dev/null
echo "sys copy rc=$? files=$(find $B/tree_sys -type f | wc -l)"
umount $B/mnts 2>/dev/null
CIL=$B/tree_sys/system/etc/selinux/plat_sepolicy.cil
grep -oE '\(type [a-zA-Z0-9_]+\)' $B/tree_sys/system/etc/selinux/*.cil 2>/dev/null | awk '{print $2}' | tr -d ')' | sort -u > $B/plat_types.txt
echo "plat types: $(wc -l < $B/plat_types.txt)"
{
  echo ""
  echo ";; ===== OriginOS port: permissive plat types (defined in this policy set) ====="
  while IFS= read -r t; do [ -n "$t" ] && echo "(typepermissive $t)"; done < $B/plat_types.txt
} >> $CIL
echo "plat cil lines: $(wc -l < $CIL)"
rm -f $B/vivo_system_v17.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v17.img $B/tree_sys 2>&1 | tail -2
ls -l $B/vivo_system_v17.img

echo "############ B. vendor v17 ############"
mkdir -p $B/mntv
mount -t erofs -o ro $B/orig_vendor.img $B/mntv || { echo "VENDOR MOUNT FAIL"; exit 1; }
cat > $B/vendor_fc <<'EOF'
/vendor u:object_r:vendor_file:s0
EOF
cd $B/mntv
find . -mindepth 1 > $B/vendor_list.txt 2>/dev/null
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/vendor/${f#./} $c" >> $B/vendor_fc
done < $B/vendor_list.txt
cd /
echo "vendor fc lines: $(wc -l < $B/vendor_fc)"
rm -rf $B/tree_vendor; mkdir -p $B/tree_vendor
cp -a $B/mntv/. $B/tree_vendor/ 2>/dev/null
echo "vendor copy rc=$? files=$(find $B/tree_vendor -type f | wc -l)"
umount $B/mntv 2>/dev/null
VCIL=$B/tree_vendor/etc/selinux/vendor_sepolicy.cil
grep -oE '\(type [a-zA-Z0-9_]+\)' $B/tree_vendor/etc/selinux/*.cil 2>/dev/null | awk '{print $2}' | tr -d ')' | sort -u > $B/vendor_types.txt
echo "vendor types: $(wc -l < $B/vendor_types.txt)"
{
  echo ""
  echo ";; ===== OriginOS port: permissive vendor types (defined in this policy set) ====="
  while IFS= read -r t; do [ -n "$t" ] && echo "(typepermissive $t)"; done < $B/vendor_types.txt
} >> $VCIL
echo "vendor cil lines: $(wc -l < $VCIL)"
rm -f $B/rothko_vendor_v17.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/vendor --file-contexts=$B/vendor_fc -T 0 $B/rothko_vendor_v17.img $B/tree_vendor 2>&1 | tail -2
ls -l $B/rothko_vendor_v17.img

echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v17.img $B/ver && { echo "sys typepermissive: $(grep -c typepermissive $B/ver/system/etc/selinux/plat_sepolicy.cil)"; grep -E '^persist.sys.usb.config=|^service.adb.tcp.port=' $B/ver/system/build.prop; umount $B/ver; }
mount -t erofs -o ro $B/rothko_vendor_v17.img $B/ver && { echo "vendor typepermissive: $(grep -c typepermissive $B/ver/etc/selinux/vendor_sepolicy.cil)"; stat -c 'VENDOR ROOT: %C' $B/ver; ls -Z $B/ver/etc/hosts 2>/dev/null | head -2; umount $B/ver; }
echo DONE
