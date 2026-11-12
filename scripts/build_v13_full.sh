#!/system/bin/sh
# Build v13 in recovery:
#  system = vivo v11 tree + rothko init.usb.rc/init.usb.configfs.rc + real model props + wifi adb
#  product = vivo product + rothko Devices overlays (correct labels)
#  odm     = rothko odm + brand=vivo (correct labels)
B=/data/local/tmp/v13
mkdir -p $B
echo "############ A. system v13 ############"
mkdir -p $B/mnts $B/mntrs
mount -t erofs -o ro $B/base_sys_v11.img $B/mnts || { echo "SYS MOUNT FAIL"; exit 1; }
cp -f $B/mnts/system/etc/selinux/plat_file_contexts $B/plat_fc
rm -rf $B/tree_sys; mkdir -p $B/tree_sys
cp -a $B/mnts/. $B/tree_sys/ 2>/dev/null
echo "sys copy rc=$? files=$(find $B/tree_sys -type f | wc -l)"
echo "--- current vivo usbd.rc ---"
head -20 $B/tree_sys/system/etc/init/usbd.rc 2>/dev/null
umount $B/mnts 2>/dev/null
echo "--- copy rothko usb rc files ---"
mount -t erofs -o ro $B/orig_rothko_system.img $B/mntrs || { echo "ROTHKO SYS MOUNT FAIL"; exit 1; }
cp -f $B/mntrs/system/etc/init/hw/init.usb.rc $B/tree_sys/system/etc/init/hw/init.usb.rc
cp -f $B/mntrs/system/etc/init/hw/init.usb.configfs.rc $B/tree_sys/system/etc/init/hw/init.usb.configfs.rc
chmod 644 $B/tree_sys/system/etc/init/hw/init.usb.rc $B/tree_sys/system/etc/init/hw/init.usb.configfs.rc
ls -l $B/tree_sys/system/etc/init/hw/init.usb*.rc
grep -n "service adbd" $B/tree_sys/system/etc/init/hw/init.usb.rc | head -3
umount $B/mntrs 2>/dev/null
# remove vivo-only usbd.rc if it references vusbd
if grep -q "vusbd" $B/tree_sys/system/etc/init/usbd.rc 2>/dev/null; then rm -f $B/tree_sys/system/etc/init/usbd.rc; echo "removed vivo usbd.rc"; fi
SBP=$B/tree_sys/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "ro.vivo.internet.name=Redmi K70 Ultra"
add_prop "ro.vivo.market.name=Redmi K70 Ultra"
add_prop "persist.sys.usb.config=adb,mtp"
add_prop "service.adb.tcp.port=5555"
add_prop "persist.adb.tcp.port=5555"
add_prop "ro.debuggable=1"
add_prop "ro.adb.secure=0"
add_prop "ro.setupwizard.mode=DISABLED"
grep -E '^ro.vivo.(internet|market).name=|^service.adb.tcp.port=|^persist.adb.tcp.port=' $SBP
cp -f $B/portfix.rc $B/tree_sys/system/etc/init/portfix.rc
cp -f $B/portfix_early.sh $B/tree_sys/system/etc/portfix_early.sh
cp -f $B/portfix_boot.sh $B/tree_sys/system/etc/portfix_boot.sh
chmod 644 $B/tree_sys/system/etc/init/portfix.rc
chmod 755 $B/tree_sys/system/etc/portfix_early.sh $B/tree_sys/system/etc/portfix_boot.sh
rm -f $B/vivo_system_v13.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v13.img $B/tree_sys 2>&1 | tail -2
ls -l $B/vivo_system_v13.img

echo "############ B. product v05 ############"
mkdir -p $B/mntpo $B/mntp3
mount -t erofs -o ro $B/orig_product.img $B/mntpo || { echo "PROD ORIG MOUNT FAIL"; exit 1; }
mount -t erofs -o ro $B/product_v03.img $B/mntp3 || { echo "PROD V03 MOUNT FAIL"; exit 1; }
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
OVL_LABEL=$(stat -c '%C' $B/mntpo/overlay/SettingsRroDeviceTypeOverlay.apk 2>/dev/null)
[ -n "$OVL_LABEL" ] || OVL_LABEL="u:object_r:vendor_file:s0"
echo "overlay label: $OVL_LABEL ; fc lines: $(wc -l < $B/product_fc)"
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

echo "############ C. odm v07 ############"
mkdir -p $B/mnto
mount -t erofs -o ro $B/orig_odm.img $B/mnto || { echo "ODM MOUNT FAIL"; exit 1; }
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
echo "odm copy rc=$? files=$(find $B/tree_odm -type f | wc -l) fc=$(wc -l < $B/odm_fc)"
umount $B/mnto 2>/dev/null
BP=$B/tree_odm/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $B/rothko_odm_v07.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=$B/odm_fc -T 0 $B/rothko_odm_v07.img $B/tree_odm 2>&1 | tail -2
ls -l $B/rothko_odm_v07.img

echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v13.img $B/ver && { grep -E '^ro.vivo.(internet|market).name=' $B/ver/system/build.prop; grep -c 'service adbd' $B/ver/system/etc/init/hw/init.usb.rc; umount $B/ver; }
mount -t erofs -o ro $B/vivo_product_v05.img $B/ver && { ls $B/ver/overlay | grep -i Device; umount $B/ver; }
mount -t erofs -o ro $B/rothko_odm_v07.img $B/ver && { stat -c 'ODM ROOT: %C' $B/ver; grep -E '^ro.product.odm.brand=' $B/ver/etc/build.prop; umount $B/ver; }
echo DONE
