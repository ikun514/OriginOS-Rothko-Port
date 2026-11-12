#!/system/bin/sh
# Rebuild odm (brand=vivo) and product (with device overlays) using CORRECT per-partition
# SELinux file_contexts files (odm_file_contexts / product_file_contexts).
B=/data/local/tmp/build
echo "=== odm v04 ==="
mkdir -p $B/mnto
mount -t erofs -o ro $B/rothko_odm_orig.img $B/mnto
echo "mount rc=$?"
rm -rf $B/tree_odm
mkdir -p $B/tree_odm
cp -a $B/mnto/. $B/tree_odm/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree_odm -type f | wc -l)"
ODMFC=$B/tree_odm/etc/selinux/odm_file_contexts
[ -f "$ODMFC" ] || ODMFC=$B/odm_file_contexts
echo "odm contexts: $ODMFC ($(wc -l < $ODMFC 2>/dev/null) lines)"
umount $B/mnto 2>/dev/null
BP=$B/tree_odm/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $B/rothko_odm_v04.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$ODMFC -T 0 $B/rothko_odm_v04.img $B/tree_odm 2>&1 | tail -3
ls -l $B/rothko_odm_v04.img

echo "=== product v04 ==="
mkdir -p $B/mntp
mount -t erofs -o ro $B/vivo_product_v03.img $B/mntp
echo "mount rc=$?"
PRODFC=$B/mntp/etc/selinux/product_file_contexts
if [ -f "$PRODFC" ]; then cp -f "$PRODFC" $B/vivo_product_file_contexts; else PRODFC=$B/product_file_contexts_rothko; fi
echo "product contexts: $PRODFC ($(wc -l < $PRODFC 2>/dev/null) lines)"
rm -rf $B/tree_prod
mkdir -p $B/tree_prod
cp -a $B/mntp/. $B/tree_prod/ 2>/dev/null
echo "copy rc=$? files=$(find $B/tree_prod -type f | wc -l)"
umount $B/mntp 2>/dev/null
ls $B/tree_prod/overlay | grep -i Device
rm -f $B/vivo_product_v04.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$PRODFC -T 0 $B/vivo_product_v04.img $B/tree_prod 2>&1 | tail -3
ls -l $B/vivo_product_v04.img

echo "=== verify mounts ==="
mkdir -p $B/mv
mount -t erofs -o ro $B/rothko_odm_v04.img $B/mv && grep -E '^ro.product.odm.brand=' $B/mv/etc/build.prop && umount $B/mv
mount -t erofs -o ro $B/vivo_product_v04.img $B/mv && ls $B/mv/overlay | grep -i Device && umount $B/mv
echo DONE
