#!/system/bin/sh
echo "=== kernel read rules in plat/vendor sepolicy (cil) ==="
grep -h "(allow kernel " /system/etc/selinux/plat_sepolicy.cil /vendor/etc/selinux/vendor_sepolicy.cil 2>/dev/null | grep -E "file" | head -40
echo "=== labels available on /data ==="
ls -Zd /data/local/tmp
ls -Z /data/local/tmp/lab 2>/dev/null
echo "=== try label variants + mount under Enforcing ==="
LAB=/data/local/tmp/lab; MNT=$LAB/mnt
cp -f $LAB/a.erofs $LAB/labelled.erofs
for ctx in system_file vendor_file rootfs apex_data_file apk_data_file system_lib_file; do
  chcon "u:object_r:$ctx:s0" $LAB/labelled.erofs 2>/dev/null || { echo "$ctx: chcon failed"; continue; }
  L=$(losetup -f 2>/dev/null); losetup "$L" $LAB/labelled.erofs 2>/dev/null
  mount -t erofs -o ro "$L" "$MNT" 2>/dev/null; rc=$?
  echo "ctx=$ctx loop=$L mount_rc=$rc"
  if [ $rc -eq 0 ]; then echo "  CONTENT: $(ls $MNT | tr '\n' ' ')"; cat $MNT/hello.txt; umount "$MNT"; fi
  losetup -d "$L" 2>/dev/null
  dmesg 2>/dev/null | tail -2 | grep -E "avc|erofs" | sed 's/^/  /'
done
echo "=== restore label ==="
chcon u:object_r:shell_data_file:s0 $LAB/labelled.erofs 2>/dev/null; ls -Z $LAB/labelled.erofs
echo "done"
