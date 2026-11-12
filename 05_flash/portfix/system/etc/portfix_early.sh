#!/system/bin/sh
# 早期 fixup：SELinux permissive + zram swap 兜底 + adb 配置
# 注意：先 setenforce，再做任何文件重定向（避免因 SELinux 拒绝写导致整个块被跳过）
setenforce 0 2>/dev/null
setprop persist.sys.usb.config adb,mtp 2>/dev/null
setprop service.adb.tcp.port 5555 2>/dev/null
{
  echo "== portfix_early $(date) =="
  echo "selinux=$(getenforce)"
  if ! grep -q zram /proc/swaps 2>/dev/null; then
    if [ -e /sys/block/zram0/disksize ]; then
      swapoff /dev/block/zram0 2>/dev/null
      echo 0 > /sys/block/zram0/disksize 2>/dev/null
      echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
      echo 6G > /sys/block/zram0/disksize 2>/dev/null
      mkswap /dev/block/zram0 >/dev/null 2>&1
      swapon /dev/block/zram0 2>&1
    fi
  fi
  cat /proc/swaps
  mkdir -p /data/misc/adb
  chmod 700 /data/misc/adb 2>/dev/null
  [ -s /data/misc/adb/adb_keys ] || cp /system/etc/portfix_adb_keys /data/misc/adb/adb_keys 2>/dev/null
  chown system:shell /data/misc/adb/adb_keys 2>/dev/null
  chmod 640 /data/misc/adb/adb_keys 2>/dev/null
  echo "usb=$(getprop persist.sys.usb.config) tcpport=$(getprop service.adb.tcp.port)"
  echo "== portfix_early done =="
} >> /data/portfix_early.log 2>&1
echo "portfix_early: selinux=$(getenforce) usb=$(getprop persist.sys.usb.config)" > /dev/kmsg 2>/dev/null
