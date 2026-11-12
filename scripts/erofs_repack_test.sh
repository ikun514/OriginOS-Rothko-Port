#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/tree $W/out $W/mnt
chcon u:object_r:system_file:s0 $W/images/*.img 2>/dev/null
echo "=== mkfs.erofs help (options of interest) ==="
mkfs.erofs --help 2>&1 | head -45
echo
echo "=== mount vivo product ==="
mount -t erofs -o ro $W/images/product.img $W/mnt
echo "mount rc=$?"
rm -rf $W/tree/product
mkdir -p $W/tree/product
echo "copy tree (cp -a) ..."
cp -a $W/mnt/. $W/tree/product/ 2>/dev/null
echo "copy rc=$?"
du -sk $W/tree/product
echo "=== repack lz4hc level9 ==="
rm -f $W/out/product_lz4hc.img
time mkfs.erofs -zlz4hc,level=9 $W/out/product_lz4hc.img $W/tree/product 2>&1 | tail -3
ls -l $W/out/product_lz4hc.img
echo "=== repack deflate level9 ==="
rm -f $W/out/product_deflate.img
mkfs.erofs -zdeflate,level=9 $W/out/product_deflate.img $W/tree/product 2>&1 | tail -3
ls -l $W/out/product_deflate.img
echo "=== original ==="
ls -l $W/images/product.img
echo "=== mount test repacked lz4hc ==="
mount -t erofs -o ro $W/out/product_lz4hc.img $W/mnt
echo "mount rc=$?"
ls $W/mnt
umount $W/mnt 2>/dev/null
echo "=== verify file count ==="
echo DONE
