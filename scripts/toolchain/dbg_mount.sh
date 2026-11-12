#!/system/bin/sh
LAB=/data/local/tmp/lab
MNT=$LAB/mnt
echo "=== 1. mount already-attached loop44 (our erofs img) ==="
mount -t erofs -o ro /dev/block/loop44 "$MNT"; echo "rc=$?"
mount | grep -F "$MNT"; ls "$MNT" 2>&1
umount "$MNT" 2>&1

echo "=== 2. detach leaked loops 44/45 ==="
losetup -d /dev/block/loop44 2>&1; losetup -d /dev/block/loop45 2>&1

echo "=== 3. losetup -f (find free) ==="
losetup -f 2>&1
LOOP=$(losetup -f 2>/dev/null)
echo "free=$LOOP"

echo "=== 4. mkfs variants and mount each ==="
rm -f $LAB/a.erofs $LAB/b.erofs $LAB/c.erofs
mkfs.erofs -d1 "$LAB/a.erofs" "$LAB/src" 2>&1 | tail -2
mkfs.erofs -d1 -x-1 "$LAB/b.erofs" "$LAB/src" 2>&1 | tail -2
mkfs.erofs -d1 -z lz4hc,level=9 "$LAB/c.erofs" "$LAB/src" 2>&1 | tail -2
for img in a b c; do
  dump.erofs $LAB/$img.erofs 2>&1 | grep -E "features|compr_algs|blocksize" | sed "s/^/  [$img] /"
done
for img in a b c; do
  L=$(losetup -f 2>/dev/null)
  [ -z "$L" ] && { echo "no free loop"; break; }
  if losetup "$L" "$LAB/$img.erofs" 2>&1; then
    mount -t erofs -o ro "$L" "$MNT"; rc=$?
    echo "[$img] loop=$L mount rc=$rc"
    if [ $rc -eq 0 ]; then ls "$MNT"; cat "$MNT/hello.txt" 2>&1; umount "$MNT"; fi
    losetup -d "$L" 2>&1
  fi
done
echo "=== done ==="
