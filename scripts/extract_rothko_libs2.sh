#!/system/bin/sh
W=/data/local/tmp/work
P=/data/local/tmp/portfix
S=/data/local/tmp/rothko_system_a.img
mkdir -p $P/rothko_lib $W/mntr
chcon u:object_r:system_file:s0 $S 2>/dev/null
mount -t erofs -o ro $S $W/mntr
echo "mount rc=$?"
SRC=$W/mntr
[ -d $W/mntr/system/lib64 ] && SRC=$W/mntr/system
echo "src=$SRC"
ls $SRC | head -8
for f in libsensorservice.so libsensorprivacy.so libsensorndkbridge.so libandroid_servers.so; do
  if [ -f "$SRC/lib64/$f" ]; then cp -f "$SRC/lib64/$f" $P/rothko_lib/ && echo "copied $f $(stat -c %s $SRC/lib64/$f)"; fi
done
chcon -R u:object_r:system_lib_file:s0 $P/rothko_lib 2>/dev/null
ls -l $P/rothko_lib/
sha256sum $P/rothko_lib/*.so 2>/dev/null
echo "=== vivo versions ==="
sha256sum /system/lib64/libsensorservice.so /system/lib64/libsensorprivacy.so /system/lib64/libsensorndkbridge.so 2>/dev/null
umount $W/mntr 2>/dev/null
echo DONE
