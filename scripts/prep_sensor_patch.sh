#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
mkdir -p $W/mnts
chcon u:object_r:system_file:s0 $W/images/system.img 2>/dev/null
mount -t erofs -o ro $W/images/system.img $W/mnts
echo "mount rc=$?"
SRC=$W/mnts
[ -d $W/mnts/system/lib64 ] && SRC=$W/mnts/system
cp -f $SRC/lib64/libsensorservice.so $P/libsensorservice_vivo.so
ls -l $P/libsensorservice_vivo.so
echo "=== convertToSensorEvent symbol ==="
readelf -sW $P/libsensorservice_vivo.so 2>/dev/null | grep -i convertToSensorEvent
echo "=== sections .plt / .rela.plt ==="
readelf -SW $P/libsensorservice_vivo.so 2>/dev/null | grep -E ' \.(plt|rela\.plt|dynsym|text)' 
echo "=== relocations (JUMP_SLOT only, first 80) ==="
readelf -rW $P/libsensorservice_vivo.so 2>/dev/null | grep -nE 'JUMP_SLOT' | head -80
echo "=== __assert2 symbols ==="
readelf -sW $P/libsensorservice_vivo.so 2>/dev/null | grep -iE 'assert|abort' | head -10
umount $W/mnts 2>/dev/null
echo DONE
