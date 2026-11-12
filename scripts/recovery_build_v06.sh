#!/system/bin/sh
# Build vivo system v06 inside recovery: v03 content + baked libs + early-adb/permissive rc + props
B=/data/local/tmp/build
T=$B/tree
FC=$B/plat_file_contexts
OUT=$B/vivo_system_v06.img
mkdir -p $B
echo "=== mount v03 ==="
mkdir -p $B/mnt
mount -t erofs -o ro $B/v03_system.img $B/mnt
echo "mount rc=$?"
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $FC 2>/dev/null
ls -l $FC 2>/dev/null
echo "=== copy tree ==="
rm -rf $T
mkdir -p $T
cp -a $B/mnt/. $T/ 2>/dev/null
echo "copy rc=$?"
echo "files: $(find $T -type f | wc -l)"
umount $B/mnt 2>/dev/null

echo "=== bake patched libs ==="
cp -f $B/libvivo_servers.so $T/system/lib64/libvivo_servers.so
cp -f $B/libsensorservice.so $T/system/lib64/libsensorservice.so
chown 0:0 $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so 2>/dev/null
chmod 644 $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so
sha256sum $T/system/lib64/libvivo_servers.so $T/system/lib64/libsensorservice.so

echo "=== add portfix rc/scripts ==="
mkdir -p $T/system/etc/init
cp -f $B/portfix.rc $T/system/etc/init/portfix.rc
cp -f $B/portfix_early.sh $T/system/etc/portfix_early.sh
cp -f $B/portfix_boot.sh $T/system/etc/portfix_boot.sh
cp -f $B/portfix_adb_keys $T/system/etc/portfix_adb_keys
chown 0:0 $T/system/etc/init/portfix.rc $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh $T/system/etc/portfix_adb_keys 2>/dev/null
chmod 644 $T/system/etc/init/portfix.rc $T/system/etc/portfix_adb_keys
chmod 755 $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh
ls -l $T/system/etc/init/portfix.rc $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh

echo "=== build.prop additions ==="
SBP=$T/system/build.prop
for line in "persist.sys.usb.config=adb,mtp" "ro.vivo.internet.name=iQOO Neo9 Pro" "ro.vivo.market.name=iQOO Neo9 Pro"; do
  k=${line%%=*}
  grep -q "^$k=" $SBP || echo "$line" >> $SBP
done
tail -4 $SBP

echo "=== mkfs.erofs ==="
rm -f $OUT
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $OUT $T 2>&1 | tail -4
ls -l $OUT
echo "=== verify mount ==="
mkdir -p $B/mnt2
mount -t erofs -o ro $OUT $B/mnt2 && ls -l $B/mnt2/system/etc/init/portfix.rc $B/mnt2/system/lib64/libvivo_servers.so && grep -E 'usb.config|market.name' $B/mnt2/system/build.prop && umount $B/mnt2
echo DONE
