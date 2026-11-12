#!/system/bin/sh
W=/data/local/tmp/work
T=$W/tree/vivo_system
P=/data/local/tmp/portfix
OUT=$W/out/vivo_system_v04.img
echo "=== 1. bake patched libs ==="
cp -f $P/libvivo_servers.so $T/system/lib64/libvivo_servers.so
cp -f $P/libsensorservice_patched.so $T/system/lib64/libsensorservice.so
chown 0:0 $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so
chmod 644 $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so
sha256sum $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so

echo "=== 2. remove SetupWizard ==="
du -sk $T/system/priv-app/SetupWizard
rm -rf $T/system/priv-app/SetupWizard
ls -d $T/system/priv-app/SetupWizard 2>/dev/null || echo "SetupWizard removed"

echo "=== 3. add portfix files ==="
mkdir -p $T/system/etc/init
cp -f $P/portfix.rc $T/system/etc/init/portfix.rc
cp -f $P/portfix_boot.sh $T/system/etc/portfix_boot.sh
cp -f $P/portfix_adb_keys $T/system/etc/portfix_adb_keys
chown 0:0 $T/system/etc/init/portfix.rc $T/system/etc/portfix_boot.sh $T/system/etc/portfix_adb_keys
chmod 644 $T/system/etc/init/portfix.rc $T/system/etc/portfix_adb_keys
chmod 755 $T/system/etc/portfix_boot.sh
ls -l $T/system/etc/init/portfix.rc $T/system/etc/portfix_boot.sh $T/system/etc/portfix_adb_keys

echo "=== 4. mkfs.erofs lz4hc level9 ==="
rm -f $OUT
time mkfs.erofs -zlz4hc,level=9 --file-contexts=$W/cfg/system_etc_selinux/plat_file_contexts -T 0 $OUT $T 2>&1 | tail -6
ls -l $OUT
echo "=== 5. mount verify ==="
mkdir -p $W/mnt2
chcon u:object_r:system_file:s0 $OUT
if mount -t erofs -o ro $OUT $W/mnt2; then
  echo "mount OK"
  ls $W/mnt2/system/lib64/libvivo_servers.so $W/mnt2/system/etc/portfix_boot.sh $W/mnt2/system/etc/init/portfix.rc 2>&1
  ls -d $W/mnt2/system/priv-app/SetupWizard 2>/dev/null || echo "no SetupWizard in image"
  umount $W/mnt2
else
  echo "MOUNT FAILED"
fi
echo DONE
