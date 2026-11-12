#!/system/bin/sh
echo "=== recovery env ==="
getenforce
which mkfs.erofs mke2fs make_f2fs lpdump 2>/dev/null
echo "=== mount test: vivo_system_v05 ==="
W=/data/local/tmp/work
mkdir -p /mnt/t1
for img in $W/out/vivo_system_v05.img $W/out/vivo_product_v03.img $W/out/rothko_odm_v03.img; do
  echo "--- $img ---"
  ls -l "$img" 2>/dev/null
  umount /mnt/t1 2>/dev/null
  mount -t erofs -o ro "$img" /mnt/t1 && echo "MOUNT OK" && ls /mnt/t1 | head -5 && umount /mnt/t1 || echo "MOUNT FAILED"
done
echo "=== key files in system image ==="
umount /mnt/t1 2>/dev/null
mount -t erofs -o ro $W/out/vivo_system_v05.img /mnt/t1 && ls -l /mnt/t1/system/lib64/libvivo_servers.so /mnt/t1/system/etc/init/portfix.rc /mnt/t1/system/build.prop 2>&1 | head -5
echo "--- portfix.rc content ---"
cat /mnt/t1/system/etc/init/portfix.rc 2>/dev/null
echo "--- setupwizard gone? ---"
ls -d /mnt/t1/system/priv-app/SetupWizard 2>/dev/null || echo "no SetupWizard"
umount /mnt/t1 2>/dev/null
echo DONE
