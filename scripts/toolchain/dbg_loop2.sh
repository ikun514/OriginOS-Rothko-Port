#!/system/bin/sh
LAB=/data/local/tmp/lab
MNT=$LAB/mnt
echo "=== free loop scan ==="
losetup -a 2>&1 | wc -l
for n in 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  [ -e /dev/block/loop$n ] || mknod /dev/block/loop$n b 7 $n 2>/dev/null
done
for n in 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  if losetup /dev/block/loop$n "$LAB/test_raw.erofs" 2>/dev/null; then echo "attached loop$n"; L=$n; break; fi
done
echo "L=$L"
[ -n "$L" ] && losetup -a | grep "loop$L"
echo "=== mount uncompressed erofs ==="
[ -n "$L" ] && { mount -t erofs -o ro /dev/block/loop$L "$MNT"; echo "rc=$?"; }
mount | grep -F "$MNT"
ls "$MNT" 2>&1
[ -n "$L" ] && umount "$MNT" 2>&1; [ -n "$L" ] && losetup -d /dev/block/loop$L 2>&1

echo "=== ext4 loop test ==="
rm -rf $LAB/extsrc; mkdir -p $LAB/extsrc
echo "ext4 hello" > $LAB/extsrc/hello.txt
mke2fs -q -t ext4 -d $LAB/extsrc $LAB/ext4.img 16384 2>&1 | head -3
ls -l $LAB/ext4.img
for n in 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  if losetup /dev/block/loop$n "$LAB/ext4.img" 2>/dev/null; then echo "attached ext4 loop$n"; E=$n; break; fi
done
echo "E=$E"
[ -n "$E" ] && { mount -t ext4 -o ro /dev/block/loop$E "$MNT"; echo "rc=$?"; }
mount | grep -F "$MNT"
cat "$MNT/hello.txt" 2>&1
ls -la "$MNT" 2>&1 | head
[ -n "$E" ] && umount "$MNT" 2>&1; [ -n "$E" ] && losetup -d /dev/block/loop$E 2>&1

echo "=== mount -o loop ext4 (kernel auto) ==="
mount -t ext4 -o loop,ro "$LAB/ext4.img" "$MNT"; echo "rc=$?"
mount | grep -F "$MNT"
cat "$MNT/hello.txt" 2>&1
umount "$MNT" 2>&1
echo "=== done ==="
