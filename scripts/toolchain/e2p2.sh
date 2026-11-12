#!/system/bin/sh
set -u
. /data/local/tmp/toolchain/dev_lib.sh
W=/data/local/tmp/lab/e2p2
rm -rf $W; mkdir -p $W/src/bin
echo hello > $W/src/hello.txt
FC=/system/etc/selinux/plat_file_contexts
echo "=== B full output: e2fsdroid -e -S fc -a /system img ==="
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d $W/src -O ^has_journal $W/t.img 16384 2>/dev/null
e2fsdroid -e -S $FC -a /system $W/t.img; echo "rc=$?"
echo "=== e2fsdroid -e ????? ==="
mount_image $W/t.img ext4 $W/mnt && { ls -Z $W/mnt; ls -Z $W/mnt/hello.txt; unmount_image $W/mnt; }
restore_image_label $W/t.img
echo "=== E: ? -e ? -f ==="
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d $W/src -O ^has_journal $W/t2.img 16384 2>/dev/null
e2fsdroid -e -f $W/src -a /system -S $FC $W/t2.img; echo "rc=$?"
echo "=== F: ?? journal ? mke2fs ==="
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d $W/src $W/t3.img 16384 2>/dev/null
e2fsdroid -e -S $FC -a /system $W/t3.img; echo "rc=$?"
echo "=== G: xattr ????: fsck.erofs --extract --xattrs ???????? ==="
IMG=/data/local/tmp/lab/comp/img/odm_dlkm_a.img
if [ ! -f "$IMG" ]; then
  dd if=/dev/block/by-name/super of=$IMG bs=512 skip=1724416 count=680 2>&1 | tail -1
fi
mkdir -p $W/xa
fsck.erofs --extract=$W/xa --overwrite --xattrs "$IMG" 2>&1 | tail -3
find $W/xa -type f | head -5
echo "--- ??????? xattr ---"
for f in $(find $W/xa -type f | head -3); do echo "$f"; ls -Z "$f"; done
echo "=== H: mke2fs -d ?? xattr ???????????? ==="
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d $W/xa -O ^has_journal $W/xa.img 16384 2>/dev/null
mount_image $W/xa.img ext4 $W/mnt && { echo "--- mounted ls -Z ---"; ls -Z $W/mnt; find $W/mnt -type f | head -5 | while read -r f; do echo "$f"; ls -Z "$f"; done; unmount_image $W/mnt; }
restore_image_label $W/xa.img
echo "=== done ==="
