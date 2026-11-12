#!/system/bin/sh
echo "=== realpaths ==="
for b in mkfs.erofs mke2fs e2fsdroid tune2fs fsck.erofs dump.erofs losetup mount; do
  p=$(which "$b" 2>/dev/null)
  if [ -n "$p" ]; then
    ls -l "$p"
  else
    echo "MISSING: $b"
  fi
done
echo "=== versions ==="
mkfs.erofs --version 2>&1 | head -3
echo "--- mke2fs"
mke2fs -V 2>&1 | head -2
echo "--- e2fsdroid -h"
e2fsdroid -h 2>&1 | head -30
echo "=== mkfs.erofs help ==="
mkfs.erofs --help 2>&1 | head -50
echo "=== selinux context files ==="
ls -l /system/etc/selinux/ 2>/dev/null
ls -l /vendor/etc/selinux/ 2>/dev/null
echo "=== existing erofs mounts ==="
grep erofs /proc/mounts | head -3
echo "=== done ==="
