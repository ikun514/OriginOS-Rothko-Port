#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
FC=$W/cfg/system_etc_selinux/plat_file_contexts

echo "############ product v03 (+device overlays) ############"
ls $W/tree/vivo_product/overlay/ | head -3
cp -f $P/overlays/DevicesAndroidOverlay.apk $P/overlays/DevicesOverlay.apk $W/tree/vivo_product/overlay/
ls -l $W/tree/vivo_product/overlay/ | grep -i Device
rm -f $W/out/vivo_product_v03.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $W/out/vivo_product_v03.img $W/tree/vivo_product 2>&1 | tail -3
ls -l $W/out/vivo_product_v03.img

echo "############ odm v03 (clean tree + brand=vivo) ############"
BP=$W/tree/rothko_odm2/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $W/out/rothko_odm_v03.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $W/out/rothko_odm_v03.img $W/tree/rothko_odm2 2>&1 | tail -3
ls -l $W/out/rothko_odm_v03.img

echo "############ verify mount ############"
mkdir -p $W/mntv2
chcon u:object_r:system_file:s0 $W/out/vivo_product_v03.img
mount -t erofs -o ro $W/out/vivo_product_v03.img $W/mntv2 && ls $W/mntv2/overlay | grep -i Device && umount $W/mntv2
chcon u:object_r:system_file:s0 $W/out/rothko_odm_v03.img
mount -t erofs -o ro $W/out/rothko_odm_v03.img $W/mntv2 && grep -E '^ro.product.odm.brand=' $W/mntv2/etc/build.prop && umount $W/mntv2
echo DONE
