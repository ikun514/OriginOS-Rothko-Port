#!/system/bin/sh
W=/data/local/tmp/work
mkdir -p $W/mnt $W/cfg
if [ ! -f $W/images/system.img ]; then
  echo "copying system.img to /data/local/tmp ..."
  time cp /sdcard/work/images/system.img $W/images/system.img
fi
chcon u:object_r:system_file:s0 $W/images/system.img
mount -t erofs -o ro $W/images/system.img $W/mnt
echo "mount rc=$?"
echo "=== vivo system top-level du (KB) ==="
du -sk $W/mnt/* 2>/dev/null | sort -n -r | head -25
echo "=== apex ==="
ls $W/mnt/apex 2>/dev/null | wc -l
du -sk $W/mnt/apex 2>/dev/null
ls $W/mnt/apex 2>/dev/null | head -30 | tr '\n' ' '
echo
echo "=== app / priv-app counts ==="
ls $W/mnt/app 2>/dev/null | wc -l
ls $W/mnt/priv-app 2>/dev/null | wc -l
echo "=== biggest apks ==="
find $W/mnt/app $W/mnt/priv-app -maxdepth 2 -name '*.apk' -printf '%s %p\n' 2>/dev/null | sort -n -r | head -25
echo "=== build.prop key ==="
grep -E '^(ro\.(product\.(system|vendor|product)\.(device|brand|model|name)|build\.(version\.release|version\.sdk|fingerprint|date)|vivo|vndk|treble)|ro\.vivo)' $W/mnt/build.prop 2>/dev/null | head -40
echo "=== compatibility matrices ==="
ls $W/mnt/etc/vintf/ 2>/dev/null | tr '\n' ' '
echo
echo "=== copy small config files to $W/cfg ==="
cp -a $W/mnt/build.prop $W/cfg/system_build.prop 2>/dev/null
cp -a $W/mnt/etc/vintf/compatibility_matrix*.xml $W/cfg/ 2>/dev/null
cp -a $W/mnt/etc/init $W/cfg/system_etc_init 2>/dev/null
cp -a $W/mnt/etc/selinux $W/cfg/system_etc_selinux 2>/dev/null
cp -a $W/mnt/etc/permissions $W/cfg/system_etc_permissions 2>/dev/null
du -sk $W/cfg
ls $W/cfg
umount $W/mnt
echo DONE
