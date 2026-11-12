#!/system/bin/sh
# v28:
#  A) system: current flashed system + raise vm.max_map_count (gallery native crash fix)
#  B) odm: odm v06 + remove vendor.xiaomi.sensor.citsensorservice rc (99% CPU spinner -> lag)
B=/data/local/tmp/v28
mkdir -p $B
echo "############ A. system v28 ############"
mkdir -p $B/mnts
mount -t erofs -o ro /dev/block/mapper/system_a $B/mnts || { echo "SYS MOUNT FAIL"; exit 1; }
cp -f $B/mnts/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree_sys; mkdir -p $B/tree_sys
cp -a $B/mnts/. $B/tree_sys/ 2>/dev/null
echo "sys copy rc=$? files=$(find $B/tree_sys -type f | wc -l)"
umount $B/mnts 2>/dev/null
RC=$B/tree_sys/system/etc/init/hw/init.usb.rc
grep -q 'vm.max_map_count' $RC || cat >> $RC <<'EOF'

# ===== OriginOS port: raise vm.max_map_count (vivo gallery bionic atexit/mprotect OOM) =====
on early-init
    write /proc/sys/vm/max_map_count 262144
EOF
tail -6 $RC
rm -f $B/vivo_system_v28.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v28.img $B/tree_sys 2>&1 | tail -2
ls -l $B/vivo_system_v28.img

echo "############ B. odm v08 ############"
mkdir -p $B/mnto
mount -t erofs -o ro $B/odm_v06.img $B/mnto || { echo "ODM MOUNT FAIL"; exit 1; }
echo "--- xiaomi sensor rc files in odm ---"
ls $B/mnto/etc/init 2>/dev/null | grep -iE 'sensor|cit'
echo "/odm u:object_r:vendor_file:s0" > $B/odm_fc
cd $B/mnto
find . -mindepth 1 > $B/odm_list.txt 2>/dev/null
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/odm/${f#./} $c" >> $B/odm_fc
done < $B/odm_list.txt
cd /
rm -rf $B/tree_odm; mkdir -p $B/tree_odm
cp -a $B/mnto/. $B/tree_odm/ 2>/dev/null
echo "odm copy rc=$? files=$(find $B/tree_odm -type f | wc -l) fc=$(wc -l < $B/odm_fc)"
umount $B/mnto 2>/dev/null
echo "--- remove citsensorservice rc ---"
rm -f $B/tree_odm/etc/init/vendor.xiaomi.sensor.citsensorservice.aidl.rc
ls $B/tree_odm/etc/init 2>/dev/null | grep -iE 'sensor|cit' || echo "citsensorservice rc removed"
grep -E '^ro.product.odm.(brand|manufacturer)=' $B/tree_odm/etc/build.prop
rm -f $B/rothko_odm_v08.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=$B/odm_fc -T 0 $B/rothko_odm_v08.img $B/tree_odm 2>&1 | tail -2
ls -l $B/rothko_odm_v08.img

echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v28.img $B/ver && { grep -c 'max_map_count' $B/ver/system/etc/init/hw/init.usb.rc; grep -E '^ro.vivo.market.name=' $B/ver/system/build.prop; umount $B/ver; }
mount -t erofs -o ro $B/rothko_odm_v08.img $B/ver && { stat -c 'ODM ROOT: %C' $B/ver; ls $B/ver/etc/init 2>/dev/null | grep -ci citsensor; grep -E '^ro.product.odm.brand=' $B/ver/etc/build.prop; umount $B/ver; }
echo DONE
