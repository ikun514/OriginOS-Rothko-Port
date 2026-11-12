#!/system/bin/sh
# Image-level permissive: executed by init via su domain at post-fs-data.
setenforce 0
echo "portfix_perm: selinux=$(getenforce)" > /dev/kmsg 2>/dev/null
mkdir -p /data/local/tmp 2>/dev/null
echo "== portfix_perm $(date) selinux=$(getenforce) ==" >> /data/portfix_perm.log 2>/dev/null
# keep 5555 for wifi adb as fallback
setprop service.adb.tcp.port 5555 2>/dev/null
setprop persist.sys.usb.config mtp,adb 2>/dev/null
echo "portfix_perm done" >> /data/portfix_perm.log 2>/dev/null
