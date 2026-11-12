#!/system/bin/sh
IMG=/data/local/tmp/lab/test.erofs
echo "=== loop nodes ==="
ls -l /dev/block/loop2 /dev/block/loop10 /dev/block/loop30 2>&1
echo "=== try losetup with stderr ==="
losetup /dev/block/loop30 "$IMG"; echo "rc=$?"
losetup -a 2>&1 | head -5
echo "=== try /dev/loop30 mknod ==="
mknod /dev/loop30 b 7 30 2>&1
ls -l /dev/loop30 2>&1
losetup /dev/loop30 "$IMG"; echo "rc=$?"
echo "=== blockdev ==="
blockdev --getsize64 "$IMG" 2>&1
echo "=== dmesg loop ==="
dmesg 2>/dev/null | tail -20
echo "=== selinux denials ==="
dmesg 2>/dev/null | grep -i avc | tail -10
echo "=== mount with -o loop directly ==="
mount -t erofs -o loop,ro "$IMG" /data/local/tmp/lab/mnt; echo "rc=$?"
mount | tail -3
echo "=== try loop-control get free via mount -t erofs ==="
mount -t erofs "$IMG" /data/local/tmp/lab/mnt; echo "rc=$?"
echo "=== lpdump test ==="
lpdump --version 2>&1 | head -2
