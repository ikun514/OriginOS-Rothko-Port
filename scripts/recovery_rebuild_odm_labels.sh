#!/system/bin/sh
# Rebuild rothko odm with brand=vivo AND preserved SELinux labels (harvested from original image)
B=/data/local/tmp/build
echo "=== mount original odm ==="
mkdir -p $B/mnto
umount $B/mnto 2>/dev/null
mount -t erofs -o ro $B/rothko_odm_orig.img $B/mnto
echo "mount rc=$?"
echo "=== harvest labels ==="
cd $B/mnto
find . -mindepth 1 > $B/odm_list.txt 2>/dev/null
echo "entries: $(wc -l < $B/odm_list.txt)"
: > $B/odm_fc_generated
while IFS= read -r f; do
  c=$(stat -c '%C' "$f" 2>/dev/null)
  [ -n "$c" ] && echo "/odm/${f#./} $c" >> $B/odm_fc_generated
done < $B/odm_list.txt
cd /
echo "fc lines: $(wc -l < $B/odm_fc_generated)"
head -3 $B/odm_fc_generated
umount $B/mnto 2>/dev/null
echo "=== patch build.prop + repack with labels ==="
BP=$B/tree_odm/etc/build.prop
sed -i 's/^ro\.product\.odm\.brand=.*/ro.product.odm.brand=vivo/; s/^ro\.product\.odm\.manufacturer=.*/ro.product.odm.manufacturer=vivo/' $BP
grep -E '^ro.product.odm.(brand|manufacturer)=' $BP
rm -f $B/rothko_odm_v05.img
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=$B/odm_fc_generated -T 0 $B/rothko_odm_v05.img $B/tree_odm 2>&1 | tail -3
ls -l $B/rothko_odm_v05.img
echo "=== verify labels in rebuilt image ==="
mkdir -p $B/mv
mount -t erofs -o ro $B/rothko_odm_v05.img $B/mv && ls -Z $B/mv/etc/build.prop $B/mv/lib64/libcam.hal.v3-impl.so 2>/dev/null | head -3; ls -Z $B/mv/bin/hw 2>/dev/null | head -3; umount $B/mv
echo DONE
