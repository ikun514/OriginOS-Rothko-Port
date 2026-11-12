#!/system/bin/sh
# KSU post-fs-data: permissive + zram swap (fix OOM deadlock) + adb defaults
mkdir -p /data/local/tmp 2>/dev/null
LOG=/data/portfix.log
{
  echo "==== $(date) post-fs-data ===="
  echo "before: $(getenforce)"
  setenforce 0 2>&1
  echo "after: $(getenforce)"

  if [ -e /sys/block/zram0/disksize ]; then
    swapoff /dev/block/zram0 2>/dev/null
    echo 0 > /sys/block/zram0/disksize 2>/dev/null
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo 6G > /sys/block/zram0/disksize 2>/dev/null
    if mkswap /dev/block/zram0 >/dev/null 2>&1; then
      swapon /dev/block/zram0 2>&1
      echo "swapon rc=$?"
    else
      echo "mkswap failed"
    fi
  else
    echo "no /sys/block/zram0"
  fi
  cat /proc/swaps

  setprop persist.sys.usb.config adb,mtp 2>&1
  echo "usb=$(getprop persist.sys.usb.config)"
  echo "==== post-fs-data done ===="
} >> "$LOG" 2>&1
