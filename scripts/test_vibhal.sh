#!/system/bin/sh
W=/data/local/tmp/work
V=/data/local/tmp/vibhal
mkdir -p $V/bin $V/lib64
chcon u:object_r:system_file:s0 $W/images/vendor.img 2>/dev/null
mount -t erofs -o ro $W/images/vendor.img $W/mntv 2>/dev/null
echo "mount rc=$?"
cp -f $W/mntv/bin/hw/vendor.vivo.hardware.vibrator.custom.service $V/bin/ 2>/dev/null
cp -f $W/mntv/lib64/vendor.aac.hardware.richtap.vibrator-V3-ndk.so $V/lib64/ 2>/dev/null
cp -f $W/mntv/lib64/vendor.aac.hardware.vibrator.custom.impl.so $V/lib64/ 2>/dev/null
cp -f $W/mntv/lib64/vibrator.default.so $V/lib64/ 2>/dev/null
cp -f $W/mntv/etc/init/vendor.vivo.hardware.vibrator.custom.service.rc $V/ 2>/dev/null
cp -f $W/mntv/etc/vintf/manifest/vendor.vivo.hardware.vibrator.custom.service.xml $V/ 2>/dev/null
chmod 755 $V/bin/*
chcon -R u:object_r:vendor_file:s0 $V
echo "=== copied files ==="
ls -lR $V | head -30
echo "=== rc content ==="
cat $V/vendor.vivo.hardware.vibrator.custom.service.rc 2>/dev/null
echo "=== try starting service manually ==="
setprop ro.vendor.vivo.vibhal.test 1
LD_LIBRARY_PATH=$V/lib64 $V/bin/vendor.vivo.hardware.vibrator.custom.service > $V/service.log 2>&1 &
sleep 4
echo "--- service.log ---"
cat $V/service.log 2>/dev/null
echo "--- service list ---"
service list 2>/dev/null | grep -i -E "richtap|vibrator|custom" 
echo DONE
