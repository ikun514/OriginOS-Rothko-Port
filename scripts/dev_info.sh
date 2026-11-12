#!/system/bin/sh
echo "== props =="
getprop ro.product.device
getprop ro.build.fingerprint
getprop ro.boot.hardware
getprop ro.boot.slot_suffix
getprop ro.build.ab_update
getprop ro.build.version.release
getprop ro.build.type
getprop ro.build.version.security_patch
echo "== filesystems =="
cat /proc/filesystems
echo "== block sizes =="
for p in super boot_a init_boot_a vendor_boot_a dtbo_a vbmeta_a vbmeta_system_a vbmeta_vendor_a; do
  sz=$(blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null)
  echo "$p $sz"
done
echo "== mapper sizes =="
for p in system_a vendor_a product_a system_ext_a odm_a odm_dlkm_a vendor_dlkm_a mi_ext_a; do
  sz=$(blockdev --getsize64 /dev/block/mapper/$p 2>/dev/null)
  echo "$p $sz"
done
echo "== mount =="
mount | grep -E ' /(system|vendor|product|odm|system_ext|mi_ext|metadata)\b'
echo "== loop support =="
ls -l /dev/loop-control 2>/dev/null
echo "== selinux =="
getenforce
echo "== cpu =="
cat /proc/cpuinfo | grep -c processor
echo "== cmdline =="
cat /proc/cmdline
echo "== free space =="
df -h /data
