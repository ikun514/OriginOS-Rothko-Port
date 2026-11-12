#!/system/bin/sh
B=/data/local/tmp
T=$B/tree_odm6
OUT=$B/rothko_odm_v06.img
FC=$B/odm_fc6
echo "=== mount original odm ==="
mkdir -p $B/mnto
umount $B/mnto 2>/dev/null
mount -t erofs -o ro $B/orig_odm.img $B/mnto
echo "mount rc=$?"
echo "=== harvest labels incl root ==="
cd $B/mnto
find . -mindepth 1 > $B/odm_list6.txt 2>/dev/null
: > $FC
echo "/odm u:object_r:vendor_file:s0" >> $FC
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/odm/${f#./} $c" >> $FC
done < $B/odm_list6.txt
cd /
echo "fc lines: $(wc -l < $FC)"; head -3 $FC
echo "=== copy tree ==="
rm -rf $T; mkdir -p $T
cp -a $B/mnto/. $T/ 2>/dev/null
echo "copy rc=$? files=$(find $T -type f | wc -l)"
umount $B/mnto 2>/dev/null
echo "=== patch brand ==="
BP=$T/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
echo "=== mkfs with root label ==="
rm -f $OUT
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=$FC -T 0 $OUT $T 2>&1 | tail -3
ls -l $OUT
echo "=== verify ==="
mkdir -p $B/mvv
mount -t erofs -o ro $OUT $B/mvv && { stat -c 'ROOT: %C' $B/mvv; ls -Z $B/mvv/etc/build.prop; ls $B/mvv | head; umount $B/mvv; }
echo DONE
