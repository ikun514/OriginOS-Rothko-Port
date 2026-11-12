#!/system/bin/sh
# Rebuild product image with rothko Devices overlays (correct SELinux labels, mount-point=/product)
B=/data/local/tmp/ovl
mkdir -p $B/mnt1 $B/mnt2
echo "=== mount images ==="
mount -t erofs -o ro $B/orig_product.img $B/mnt1 || { echo "ORIG MOUNT FAIL"; exit 1; }
mount -t erofs -o ro $B/product_v03.img $B/mnt2 || { echo "V03 MOUNT FAIL"; exit 1; }
echo "orig files: $(find $B/mnt1 -type f | wc -l)  v03 files: $(find $B/mnt2 -type f | wc -l)"
echo "=== build file_contexts from original product labels ==="
echo "/product u:object_r:vendor_file:s0" > $B/product_fc
cd $B/mnt1
find . -mindepth 1 > $B/prod_list.txt 2>/dev/null
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/product/${f#./} $c" >> $B/product_fc
done < $B/prod_list.txt
cd /
OVL_LABEL=$(stat -c '%C' $B/mnt1/overlay/SettingsRroDeviceTypeOverlay.apk 2>/dev/null)
[ -n "$OVL_LABEL" ] || OVL_LABEL="u:object_r:vendor_file:s0"
echo "fc lines: $(wc -l < $B/product_fc)  overlay label: $OVL_LABEL"
echo "=== copy tree from v03 (contains overlays) ==="
rm -rf $B/tree; mkdir -p $B/tree
cp -a $B/mnt2/. $B/tree/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree -type f | wc -l)"
ls $B/tree/overlay | grep -i Device
echo "/product/overlay/DevicesAndroidOverlay.apk $OVL_LABEL" >> $B/product_fc
echo "/product/overlay/DevicesOverlay.apk $OVL_LABEL" >> $B/product_fc
umount $B/mnt1 $B/mnt2 2>/dev/null
echo "=== repack ==="
rm -f $B/vivo_product_v05.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/product --file-contexts=$B/product_fc -T 0 $B/vivo_product_v05.img $B/tree 2>&1 | tail -2
ls -l $B/vivo_product_v05.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_product_v05.img $B/ver && {
  stat -c 'PROD ROOT: %C' $B/ver
  ls -lZ $B/ver/overlay/DevicesOverlay.apk $B/ver/overlay/DevicesAndroidOverlay.apk
  umount $B/ver
}
echo DONE
