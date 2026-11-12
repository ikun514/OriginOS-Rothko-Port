#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
S=/sdcard/work/rothko_system_a.img
mkdir -p $P/rothko_lib $W/mntr
[ -f $S ] || echo "MISSING $S"
chcon u:object_r:system_file:s0 $S 2>/dev/null
mount -t erofs -o ro $S $W/mntr 2>/dev/null || { chcon u:object_r:system_file:s0 $S; mount -t erofs -o ro $S $W/mntr; }
echo "mount rc=$?"
# rothko system image root has system/ subdir
SRC=$W/mntr
[ -d $SRC/system/lib64 ] && SRC=$W/mntr/system
echo "using src $SRC"
for f in libsensorservice.so libsensorprivacy.so libsensorndkbridge.so; do
  if [ -f "$SRC/lib64/$f" ]; then cp -f "$SRC/lib64/$f" $P/rothko_lib/ && echo "copied $f"; fi
done
ls -l $P/rothko_lib/
chcon -R u:object_r:system_lib_file:s0 $P/rothko_lib 2>/dev/null
sha256sum $P/rothko_lib/*.so 2>/dev/null
umount $W/mntr 2>/dev/null
echo DONE
