#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
FC=$W/cfg/system_etc_selinux/plat_file_contexts

echo "############ A. product v02 (vivo product + rothko Device overlays) ############"
mkdir -p $W/mntp
chcon u:object_r:system_file:s0 $W/images/product.img 2>/dev/null
mount -t erofs -o ro $W/images/product.img $W/mntp || { chcon u:object_r:system_file:s0 $W/images/product.img; mount -t erofs -o ro $W/images/product.img $W/mntp; }
echo "mount rc=$?"
rm -rf $W/tree/vivo_product
mkdir -p $W/tree/vivo_product
cp -a $W/mntp/. $W/tree/vivo_product/ 2>/dev/null
echo "copy rc=$?"
umount $W/mntp 2>/dev/null
echo "--- add overlays ---"
ls -l $P/overlays/
cp -f $P/overlays/*.apk $W/tree/vivo_product/overlay/ 2>/dev/null
ls -l $W/tree/vivo_product/overlay/ | grep -iE 'Device' 
echo "--- repack ---"
rm -f $W/out/vivo_product_v02.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $W/out/vivo_product_v02.img $W/tree/vivo_product 2>&1 | tail -3
ls -l $W/out/vivo_product_v02.img

echo "############ B. odm v02 (rothko odm + brand=vivo) ############"
mkdir -p $W/mnto
chcon u:object_r:system_file:s0 /data/local/tmp/rothko_odm_a.img 2>/dev/null
mount -t erofs -o ro /data/local/tmp/rothko_odm_a.img $W/mnto || { chcon u:object_r:system_file:s0 /data/local/tmp/rothko_odm_a.img; mount -t erofs -o ro /data/local/tmp/rothko_odm_a.img $W/mnto; }
echo "mount rc=$?"
rm -rf $W/tree/rothko_odm
mkdir -p $W/tree/rothko_odm
cp -a $W/mnto/. $W/tree/rothko_odm/ 2>/dev/null
echo "copy rc=$?"
umount $W/mnto 2>/dev/null
BP=$W/tree/rothko_odm/etc/build.prop
echo "--- before ---"
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
echo "--- after ---"
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $W/out/rothko_odm_v02.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $W/out/rothko_odm_v02.img $W/tree/rothko_odm 2>&1 | tail -3
ls -l $W/out/rothko_odm_v02.img

echo "############ C. system v05 (add ro.vivo market props) ############"
SBP=$W/tree/vivo_system/system/build.prop
grep -q '^ro.vivo.internet.name=' $SBP || printf '\n# OriginOS port: about-phone model\nro.vivo.internet.name=iQOO Neo9 Pro\nro.vivo.market.name=iQOO Neo9 Pro\n' >> $SBP
tail -5 $SBP
rm -f $W/out/vivo_system_v05.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $W/out/vivo_system_v05.img $W/tree/vivo_system 2>&1 | tail -3
ls -l $W/out/vivo_system_v05.img
echo DONE
