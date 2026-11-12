#!/system/bin/sh
B=/data/local/tmp/sysbuild
T=$B/tree
OUT=$B/vivo_system_v11.img
FC=$B/plat_file_contexts
echo "=== concat base v10 ==="
cat /data/local/tmp/sysparts/sys.part00 /data/local/tmp/sysparts/sys.part01 /data/local/tmp/sysparts/sys.part02 /data/local/tmp/sysparts/sys.part03 /data/local/tmp/sysparts/sys.part04 > $B/base_v10.img
ls -l $B/base_v10.img
echo "=== mount + copy tree ==="
mkdir -p $B/mnt
mount -t erofs -o ro $B/base_v10.img $B/mnt
echo "mount rc=$?"
cp -f $B/mnt/system/etc/selinux/plat_file_contexts $FC
echo "plat fc lines: $(wc -l < $FC)"
rm -rf $T; mkdir -p $T
cp -a $B/mnt/. $T/ 2>/dev/null
echo "copy rc=$? files=$(find $T -type f | wc -l)"
umount $B/mnt 2>/dev/null
echo "=== remove SetupWizard + props + fixups ==="
rm -rf $T/system/priv-app/SetupWizard
ls -d $T/system/priv-app/SetupWizard 2>/dev/null && echo "STILL THERE" || echo "SetupWizard removed"
SBP=$T/system/build.prop
add_prop() { k=${1%%=*}; if grep -q "^$k=" $SBP; then sed -i "s|^$k=.*|$1|" $SBP; else echo "$1" >> $SBP; fi; }
add_prop "ro.setupwizard.mode=DISABLED"
add_prop "persist.sys.usb.config=adb,mtp"
add_prop "ro.debuggable=1"
add_prop "service.adb.root=1"
add_prop "ro.adb.secure=0"
add_prop "ro.vivo.internet.name=iQOO Neo9 Pro"
add_prop "ro.vivo.market.name=iQOO Neo9 Pro"
tail -7 $SBP
cp -f $B/portfix.rc $T/system/etc/init/portfix.rc
cp -f $B/portfix_early.sh $T/system/etc/portfix_early.sh
cp -f $B/portfix_boot.sh $T/system/etc/portfix_boot.sh
chmod 644 $T/system/etc/init/portfix.rc
chmod 755 $T/system/etc/portfix_early.sh $T/system/etc/portfix_boot.sh
echo "=== mkfs.erofs ==="
rm -f $OUT
mkfs.erofs -zlz4hc,level=9 --file-contexts=$FC -T 0 $OUT $T 2>&1 | tail -3
ls -l $OUT
echo "=== verify ==="
mkdir -p $B/mv3
mount -t erofs -o ro $OUT $B/mv3 && { (ls -d $B/mv3/system/priv-app/SetupWizard 2>/dev/null || echo "no SetupWizard OK"); grep -E 'setupwizard.mode|adb.secure|debuggable=' $B/mv3/system/build.prop; umount $B/mv3; }
echo DONE
