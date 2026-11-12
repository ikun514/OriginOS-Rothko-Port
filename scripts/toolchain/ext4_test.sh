#!/system/bin/sh
# ext4_test.sh -- 手机上验证 ext4 打包: 目录 -> mke2fs -d (+e2fsdroid SELinux 标签) -> loop 挂载 -> sha256 校验
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

WORK=/data/local/tmp/lab/ext4
SRC=$WORK/src
MNT=$WORK/mnt
IMG=$WORK/system_ext4.img
rm -rf "$WORK"; mkdir -p "$SRC/sub" "$MNT"
echo "hello ext4 roundtrip" > "$SRC/hello.txt"
echo "nested file" > "$SRC/sub/nested.txt"
head -c 131072 /dev/urandom > "$SRC/sub/rand.bin"
mkdir -p "$SRC/bin"
printf '#!/system/bin/sh\necho hi\n' > "$SRC/bin/test.sh"
chmod 755 "$SRC/bin/test.sh"
ln -s /system/bin/sh "$SRC/bin/sh"

echo "=== 1. mke2fs -d 从目录建 ext4 ==="
"$HERE/pack_ext4.sh" "$SRC" "$IMG" $((64*1024*1024)) --label system --mount-point /system 2>&1 | tail -20

echo "=== 2. tune2fs 检查 ==="
tune2fs -l "$IMG" 2>/dev/null | grep -E "volume name|Block count|Block size|Filesystem features|Inode size" | head -8

echo "=== 3. loop 挂载 ==="
mount_image "$IMG" ext4 "$MNT" || die "mount ext4 failed"
mount | grep -F "$MNT"
echo "--- ls -Z (SELinux xattr, 挂载后由 seclabel 处理) ---"
ls -la "$MNT" 2>&1 | head -10
echo "--- file content ---"
cat "$MNT/hello.txt" 2>&1

echo "=== 4. sha256 校验 ==="
tree_sha256 "$SRC" > "$WORK/src.sha256"
tree_sha256 "$MNT" > "$WORK/mnt.sha256"
echo "--- src ---"; cat "$WORK/src.sha256"
echo "--- mnt ---"; cat "$WORK/mnt.sha256"
if diff -q "$WORK/src.sha256" "$WORK/mnt.sha256" > /dev/null 2>&1; then
    echo "CHECKSUMS_MATCH"
else
    echo "CHECKSUM_MISMATCH"; diff "$WORK/src.sha256" "$WORK/mnt.sha256" | head -10
fi

echo "=== 5. 卸载 ==="
unmount_image "$MNT"
restore_image_label "$IMG"
echo "=== done ==="
