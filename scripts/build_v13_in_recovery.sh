#!/system/bin/sh
B=/data/local/tmp/v13
mkdir -p $B
echo "############ A. system v13: v11 + real model props ############"
cat /data/local/tmp/v13/sys.part00 /data/local/tmp/v13/sys.part01 /data/local/tmp/v13/sys.part02 /data/local/tmp/v13/sys.part03 /data/local/tmp/v13/sys.part04 > $B/base_sys_v11.img
ls -l $B/base_sys_v11.img
mkdir -p $B/mnts
mount -t erofs -o ro $B/base_sys_v11.img $B/mnts
echo "mount rc=$?"
cp -f $B/mnts/system/etc/selinux/plat_file_contexts $B/plat_fc
SYSFC=$B/plat_fc
rm -rf $B/tree_sys; mkdir -p $B/tree_sys
cp -a $B/mnts/. $B/tree_sys/ 2>/dev/null
echo "sys copy rc=$? files=$(find $B/tree_sys -type f | wc -l)"
umount $B/mnts 2>/dev/null
SBP=$B/tree_sys/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "ro.vivo.internet.name=Redmi K70 Ultra"
add_prop "ro.vivo.market.name=Redmi K70 Ultra"
grep -E '^ro.vivo.(internet|market).name=' $SBP
cp -f /data/local/tmp/v13/portfix.rc $B/tree_sys/system/etc/init/portfix.rc
cp -f /data/local/tmp/v13/portfix_early.sh $B/tree_sys/system/etc/portfix_early.sh
cp -f /data/local/tmp/v13/portfix_boot.sh $B/tree_sys/system/etc/portfix_boot.sh
chmod 644 $B/tree_sys/system/etc/init/portfix.rc
chmod 755 $B/tree_sys/system/etc/portfix_early.sh $B/tree_sys/system/etc/portfix_boot.sh
rm -f $B/vivo_system_v13.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$SYSFC -T 0 $B/vivo_system_v13.img $B/tree_sys 2>&1 | tail -2
ls -l $B/vivo_system_v13.img

echo "############ B. product v05: vivo product + device overlays (correct labels) ############"
mkdir -p $B/mntpo $B/mntp3
mount -t erofs -o ro /data/local/tmp/v13/orig_product.img $B/mntpo
mount -t erofs -o ro /data/local/tmp/v13/product_v03.img $B/mntp3
echo "mounts rc=$?"
cat > $B/product_fc <<'EOF'
/product u:object_r:vendor_file:s0
EOF
cd $B/mntpo
find . -mindepth 1 > $B/prod_list.txt 2>/dev/null
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/product/${f#./} $c" >> $B/product_fc
done < $B/prod_list.txt
cd /
echo "product fc lines: $(wc -l < $B/product_fc)"
# label for new overlay apks: take label of an existing overlay apk
OVL_LABEL=$(stat -c '%C' $B/mntpo/overlay/SettingsRroDeviceTypeOverlay.apk 2>/dev/null)
[ -n "$OVL_LABEL" ] || OVL_LABEL="u:object_r:vendor_file:s0"
echo "overlay label: $OVL_LABEL"
rm -rf $B/tree_prod; mkdir -p $B/tree_prod
cp -a $B/mntp3/. $B/tree_prod/ 2>/dev/null
echo "prod copy rc=$? files=$(find $B/tree_prod -type f | wc -l)"
ls $B/tree_prod/overlay | grep -i Device
echo "/product/overlay/DevicesAndroidOverlay.apk $OVL_LABEL" >> $B/product_fc
echo "/product/overlay/DevicesOverlay.apk $OVL_LABEL" >> $B/product_fc
umount $B/mntpo $B/mntp3 2>/dev/null
rm -f $B/vivo_product_v05.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/product --file-contexts=$B/product_fc -T 0 $B/vivo_product_v05.img $B/tree_prod 2>&1 | tail -2
ls -l $B/vivo_product_v05.img

echo "############ C. odm v07: odm v06 + labels ############"
mkdir -p $B/mnto
mount -t erofs -o ro $B/rothko_odm_v06.img $B/mnto 2>/dev/null || mount -t erofs -o ro /data/local/tmp/v13/orig_odm.img $B/mnto
echo "odm mount rc=$?"
cat > $B/odm_fc <<'EOF'
/odm u:object_r:vendor_file:s0
EOF
cd $B/mnto
find . -mindepth 1 > $B/odm_list.txt 2>/dev/null
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/odm/${f#./} $c" >> $B/odm_fc
done < $B/odm_list.txt
cd /
rm -rf $B/tree_odm; mkdir -p $B/tree_odm
cp -a $B/mnto/. $B/tree_odm/ 2>/dev/null
echo "odm copy rc=$? files=$(find $B/tree_odm -type f | wc -l)"
umount $B/mnto 2>/dev/null
BP=$B/tree_odm/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $B/rothko_odm_v07.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=$B/odm_fc -T 0 $B/rothko_odm_v07.img $B/tree_odm 2>&1 | tail -2
ls -l $B/rothko_odm_v07.img

echo "=== verify all ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v13.img $B/ver && { grep -E '^ro.vivo.(internet|market).name=' $B/ver/system/build.prop; umount $B/ver; }
mount -t erofs -o ro $B/vivo_product_v05.img $B/ver && { ls $B/ver/overlay | grep -i Device; stat -c 'PROD ROOT: %C' $B/ver; umount $B/ver; }
mount -t erofs -o ro $B/rothko_odm_v07.img $B/ver && { stat -c 'ODM ROOT: %C' $B/ver; grep -E '^ro.product.odm.brand=' $B/ver/etc/build.prop; umount $B/ver; }
echo DONE
