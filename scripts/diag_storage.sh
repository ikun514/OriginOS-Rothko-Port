#!/system/bin/sh
echo "===== fstab userdata / media lines ====="
grep -nE 'userdata|/data |/data/media|metadata' /vendor/etc/fstab.mt6989 2>/dev/null | head -10
echo
echo "===== first stage fstab (if visible) ====="
ls -l /first_stage_ramdisk/fstab.mt6989 2>/dev/null
grep -nE 'userdata|/data |metadata' /first_stage_ramdisk/fstab.mt6989 2>/dev/null | head -10
echo
echo "===== crypto / storage props ====="
getprop | grep -iE 'crypto|storage|vold|fbe|fde' | head -20
echo
echo "===== mounts data ====="
cat /proc/mounts | grep -E ' /data |emulated|media' | head -10
echo
echo "===== vold logs (dmesg) ====="
dmesg 2>/dev/null | grep -iE 'vold|fuse|sdcard|emulated|/data' | tail -25
echo
echo "===== sm list-volumes / disks ====="
sm list-volumes 2>&1
sm list-disks 2>&1
echo
echo "===== storage service dump ====="
dumpsys mount 2>/dev/null | head -40
echo
echo "===== /storage dirs ====="
ls -la /storage/emulated /storage/emulated/0 2>&1 | head -10
ls -la /mnt/user/0 2>&1 | head -10
echo DONE
