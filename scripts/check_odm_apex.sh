#!/system/bin/sh
echo "=== flashed odm (mapper odm_a) ==="
mkdir -p /mnt/o
mount -t erofs -o ro /dev/block/mapper/odm_a /mnt/o 2>&1; echo "mount rc=$?"
echo "--- /odm root ---"
stat -c '%C %A %U:%G %n' /mnt/o 2>&1
echo "--- /odm/apex ---"
ls -ldZ /mnt/o/apex 2>&1
ls -lZ /mnt/o/apex 2>&1 | head -10
echo "--- apex dir content count ---"
ls /mnt/o/apex 2>/dev/null | wc -l
echo "--- odm_file_contexts lines ---"
wc -l /mnt/o/etc/selinux/odm_file_contexts 2>&1
head -5 /mnt/o/etc/selinux/odm_file_contexts 2>&1
echo "=== system v11 apexd policy files ==="
mkdir -p /mnt/s
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>&1; echo "mount rc=$?"
ls -l /mnt/s/system/apex 2>&1 | head -10
ls -lZ /mnt/s/system/apex 2>&1 | head -5
umount /mnt/o 2>/dev/null; umount /mnt/s 2>/dev/null
echo DONE
