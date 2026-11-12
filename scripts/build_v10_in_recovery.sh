#!/system/bin/sh
# Build vivo system v10 in recovery:
#  v06 base (v03 content + baked libs + portfix files) + zram swap rc + service-based fixups + props
B=/data/local/tmp/sysbuild
T=$B/tree
OUT=$B/vivo_system_v10.img
FC=$B/plat_file_contexts
mkdir -p $B
echo "=== concat base ==="
cat /data/local/tmp/sysparts/sys.part00 /data/local/tmp/sysparts/sys.part01 /data/local/tmp/sysparts/sys.part02 /data/local/tmp/sysparts/sys.part03 /data/local/tmp/sysparts/sys.part04 > $B/base_v06.img
ls -l $B/base_v06.img
echo "=== mount base ==="
mkdir -p $B/mnt
mount -t erofs -o ro $B/base_v06.img $B/mnt
echo "mount rc=$?"
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $FC
echo "plat fc lines: $(wc -l < $FC)"
echo "=== copy tree ==="
rm -rf $T; mkdir -p $T
cp -a $B/mnt/. $T/ 2>/dev/null
echo "copy rc=$? files=$(find $T -type f | wc -l)"
umount $B/mnt 2>/dev/null
echo "=== install new fixups ==="
cp -f /data/local/tmp/sysbuild/portfix.rc $T/system/etc/init/portfix.rc
cp -f /data/local/tmp/sysbuild/portfix_early.sh $T/system/etc/portfix_early.sh
cp -f /data/local/tmp/sysbuild/portfix_boot.sh $T/system/etc/portfix_boot.sh
chown 0:0 $T/system/etc/init/portfix.rc $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh 2>/dev/null
chmod 644 $T/system/etc/init/portfix.rc
chmod 755 $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh
cat $T/system/etc/init/portfix.rc | head -8
echo "=== build.prop additions ==="
SBP=$T/system/build.prop
add_prop() {
  k=${1%%=*}
  if grep -q "^$k=" $SBP; then
    sed -i "s|^$k=.*|$1|" $SBP
  else
    echo "$1" >> $SBP
  fi
}
add_prop "persist.sys.usb.config=adb,mtp"
add_prop "ro.setupwizard.mode=DISABLED"
add_prop "ro.debuggable=1"
add_prop "service.adb.root=1"
add_prop "ro.vivo.internet.name=iQOO Neo9 Pro"
add_prop "ro.vivo.market.name=iQOO Neo9 Pro"
tail -8 $SBP
echo "=== mkfs.erofs ==="
rm -f $OUT
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $OUT $T 2>&1 | tail -3
ls -l $OUT
echo "=== verify ==="
mkdir -p $B/mv
mount -t erofs -o ro $OUT $B/mv && { grep -E 'usb.config|setupwizard.mode|debuggable|market.name' $B/mv/system/build.prop; head -5 $B/mv/system/etc/init/portfix.rc; ls -l $B/mv/system/etc/portfix_early.sh; umount $B/mv; }
echo DONE
