#!/system/bin/sh
LAB=/data/local/tmp/lab
MNT=$LAB/mnt
echo "=== A. loop read test on attached erofs (a.erofs) ==="
L=$(losetup -f 2>/dev/null); echo "free loop=$L"
losetup "$L" "$LAB/a.erofs"; echo "losetup rc=$?"
ls -l "$L"
echo "--- dd first 64 bytes from loop ---"
dd if="$L" bs=512 count=1 2>/dev/null | xxd | head -4
echo "--- mount ext4 control test ---"
rm -rf $LAB/extsrc; mkdir -p $LAB/extsrc; echo "ext4 hello" > $LAB/extsrc/hello.txt
mke2fs -q -t ext4 -d $LAB/extsrc $LAB/ext4.img 16384 2>&1 | head -2
L2=$(losetup -f 2>/dev/null); echo "ext4 loop=$L2"
losetup "$L2" "$LAB/ext4.img"; echo "losetup rc=$?"
dd if="$L2" bs=512 count=1 2>/dev/null | xxd | head -2
mount -t ext4 -o ro "$L2" "$MNT"; echo "mount ext4 rc=$?"
mount | grep -F "$MNT"; ls -la "$MNT" 2>&1 | head -5; cat "$MNT/hello.txt" 2>&1
umount "$MNT" 2>/dev/null
echo "=== B. setenforce 0 then erofs mount ==="
setenforce 0; getenforce
mount -t erofs -o ro "$L" "$MNT"; echo "erofs mount rc=$?"
mount | grep -F "$MNT"; ls "$MNT" 2>&1
cat "$MNT/hello.txt" 2>&1
umount "$MNT" 2>/dev/null
setenforce 1; getenforce
echo "=== C. cleanup ==="
losetup -d "$L" 2>&1; losetup -d "$L2" 2>&1
losetup -a | grep -c loop
echo "=== D. dmesg erofs ==="
dmesg 2>/dev/null | grep -i erofs | tail -10
echo "done"
