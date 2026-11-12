#!/system/bin/sh
# lab_erofs_test.sh -- 在手机上实测：目录 -> erofs 镜像 -> loop 挂载 -> 内容校验
# 只写 /data/local/tmp，不碰真实分区
LAB=/data/local/tmp/lab
MNT=$LAB/mnt
IMG=$LAB/test.erofs
MKFS=/system/bin/mkfs.erofs

fail() { echo "FAIL: $*"; exit 1; }

echo "=== 0. prep ==="
rm -rf "$LAB"; mkdir -p "$LAB/src/sub/deep" "$MNT"
echo "hello erofs roundtrip v1" > "$LAB/src/hello.txt"
echo "second file" > "$LAB/src/sub/n.txt"
echo "deep" > "$LAB/src/sub/deep/d.bin"
head -c 65536 /dev/urandom > "$LAB/src/sub/deep/rand.bin"
ln -s hello.txt "$LAB/src/link.txt"
echo "SRC_DONE"

echo "=== 1. mkfs.erofs (uncompressed) ==="
$MKFS -d2 -T 1700000000 "$LAB/test_raw.erofs" "$LAB/src" 2>&1 | tail -5
echo "rc=$?"
ls -l "$LAB/test_raw.erofs"

echo "=== 2. mkfs.erofs (lz4hc,level=9, cluster 16K) ==="
$MKFS -d2 -z lz4hc,level=9 -C16384 -T 1700000000 "$IMG" "$LAB/src" 2>&1 | tail -6
echo "rc=$?"
ls -l "$IMG"

echo "=== 3. fsck.erofs on image ==="
/system/bin/fsck.erofs "$IMG" 2>&1 | head -10

echo "=== 4. dump.erofs superblock ==="
/system/bin/dump.erofs "$IMG" 2>&1 | head -30

echo "=== 5. mount via losetup ==="
LOOP=""
for n in 40 39 38 37 36 35 34 33 32 31 30 29 28 27 26 25 24 23 22 21 20; do
  if [ ! -e /dev/block/loop$n ]; then
    mknod /dev/block/loop$n b 7 $n 2>/dev/null
  fi
  if losetup /dev/block/loop$n "$IMG" 2>/dev/null; then LOOP=/dev/block/loop$n; break; fi
done
echo "LOOP=$LOOP"
[ -z "$LOOP" ] && fail "no free loop device"
losetup -a 2>&1 | grep -F "$LOOP"
mount -t erofs -o ro "$LOOP" "$MNT"
rc=$?
echo "mount rc=$rc"
mount | grep -F "$MNT"

echo "=== 6. content verify ==="
(cd "$LAB/src" && find . -type f -exec sha256sum {} \; | sort -k2) > "$LAB/src.sums"
(cd "$MNT" && find . -type f -exec sha256sum {} \; | sort -k2) > "$LAB/mnt.sums"
cat "$LAB/src.sums"
echo "--- diff ---"
diff "$LAB/src.sums" "$LAB/mnt.sums" && echo "CHECKSUMS_MATCH"
echo "--- symlink ---"
readlink "$MNT/link.txt"
echo "--- selinux context of mounted file ---"
ls -Z "$MNT/hello.txt" 2>&1

echo "=== 7. cleanup ==="
umount "$MNT"
losetup -d "$LOOP" 2>&1
echo "LOOP_DETACHED"
mount | grep -cF "$MNT"
echo "=== ALL DONE ==="
