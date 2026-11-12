#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnt
chcon u:object_r:system_file:s0 $W/out/*.img 2>/dev/null
ls -lZ $W/out/*.img 2>/dev/null
for f in product_lz4hc.img product_deflate.img; do
  echo "=== mount $f ==="
  mount -t erofs -o ro $W/out/$f $W/mnt
  echo "rc=$?"
  if mountpoint -q $W/mnt; then
    echo "OK mounted:"
    ls $W/mnt
    # verify a file readable
    find $W/mnt -maxdepth 2 -type f 2>/dev/null | head -3
    dd if=$W/mnt/app/$(ls $W/mnt/app 2>/dev/null | head -1) bs=4096 count=1 2>/dev/null | wc -c
    umount $W/mnt
  fi
done
echo "=== erofs feature of repacked ==="
dump.erofs -s $W/out/product_deflate.img 2>&1 | grep -Ei 'feature|compr|blocks'
echo DONE
