#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnt $W/tree
mount -t erofs -o ro $W/images/system.img $W/mnt 2>/dev/null || { chcon u:object_r:system_file:s0 $W/images/system.img; mount -t erofs -o ro $W/images/system.img $W/mnt; }
echo "=== vivo system: system/ subdir du ==="
du -sk $W/mnt/system/* 2>/dev/null | sort -n -r | head -18
echo "=== apk count / total ==="
find $W/mnt/system -name '*.apk' 2>/dev/null | wc -l
find $W/mnt/system -name '*.apk' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print "apk bytes", s}'
echo "=== biggest files in whole image ==="
find $W/mnt -type f -printf '%s %p\n' 2>/dev/null | sort -n -r | head -20
echo "=== copy tree (cp -a) ==="
rm -rf $W/tree/vivo_system
mkdir -p $W/tree/vivo_system
time cp -a $W/mnt/. $W/tree/vivo_system/ 2>/dev/null
echo "copy rc=$?"
du -sk $W/tree/vivo_system
umount $W/mnt
echo "=== repack lz4hc level12 ==="
rm -f $W/out/vivo_system_lz4hc.img
time mkfs.erofs -zlz4hc,level=12 $W/out/vivo_system_lz4hc.img $W/tree/vivo_system 2>&1 | tail -4
ls -l $W/out/vivo_system_lz4hc.img $W/images/system.img
echo DONE
