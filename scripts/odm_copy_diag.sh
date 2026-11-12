#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnto
chcon u:object_r:system_file:s0 /data/local/tmp/rothko_odm_a.img 2>/dev/null
mount -t erofs -o ro /data/local/tmp/rothko_odm_a.img $W/mnto
echo "mount rc=$?"
rm -rf $W/tree/rothko_odm2
mkdir -p $W/tree/rothko_odm2
echo "=== cp -a with errors ==="
cp -a $W/mnto/. $W/tree/rothko_odm2/ 2>&1 | head -30
echo "cp rc=$?"
echo "=== compare counts ==="
echo "src:  $(find $W/mnto -type f | wc -l)"
echo "tree: $(find $W/tree/rothko_odm2 -type f | wc -l)"
echo "=== find missing big files ==="
for d in lib64 lib etc firmware; do
  echo "-- $d: src=$(du -sb $W/mnto/$d 2>/dev/null | cut -f1) tree=$(du -sb $W/tree/rothko_odm2/$d 2>/dev/null | cut -f1)"
done
umount $W/mnto 2>/dev/null
echo DONE
