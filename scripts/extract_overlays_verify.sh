#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
M=/data/local/tmp/mnt_rothko_product
echo "=== mount rothko product ==="
mkdir -p $M $P/overlays
chcon u:object_r:system_file:s0 /data/local/tmp/rothko_product_a.img 2>/dev/null
mount -t erofs -o ro /data/local/tmp/rothko_product_a.img $M || { chcon u:object_r:system_file:s0 /data/local/tmp/rothko_product_a.img; mount -t erofs -o ro /data/local/tmp/rothko_product_a.img $M; }
echo "mount rc=$?"
L=$M
[ -d "$M/system/overlay" ] && L="$M/system"
echo "src=$L"
ls "$L/overlay/" | grep -iE 'Device' 
for f in "$L/overlay/DevicesAndroidOverlay.apk" "$L/overlay/DevicesOverlay.apk"; do
  if [ -f "$f" ]; then
    cp -f "$f" $P/overlays/ && echo "copied: $f -> $(stat -c %s $P/overlays/$(basename $f))"
  else
    echo "NOT FOUND: $f"
  fi
done
ls -l $P/overlays/
echo "=== odm copy verification ==="
mkdir -p $W/mnto
chcon u:object_r:system_file:s0 /data/local/tmp/rothko_odm_a.img 2>/dev/null
mount -t erofs -o ro /data/local/tmp/rothko_odm_a.img $W/mnto || { chcon u:object_r:system_file:s0 /data/local/tmp/rothko_odm_a.img; mount -t erofs -o ro /data/local/tmp/rothko_odm_a.img $W/mnto; }
SRC_FILES=$(find $W/mnto -type f 2>/dev/null | wc -l)
SRC_BYTES=$(du -sb $W/mnto 2>/dev/null | cut -f1)
TREE_FILES=$(find $W/tree/rothko_odm -type f 2>/dev/null | wc -l)
TREE_BYTES=$(du -sb $W/tree/rothko_odm 2>/dev/null | cut -f1)
echo "odm source: files=$SRC_FILES bytes=$SRC_BYTES"
echo "odm tree  : files=$TREE_FILES bytes=$TREE_BYTES"
umount $W/mnto 2>/dev/null
echo DONE
