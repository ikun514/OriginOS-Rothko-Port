#!/system/bin/sh
# device_probe.sh -- 探测手机上可用的镜像打包/挂载能力
# 用法（PC 端）: adb push device_probe.sh /data/local/tmp/ && adb shell su -c 'sh /data/local/tmp/device_probe.sh'
LAB=/data/local/tmp/probe
BB=/data/adb/ksu/bin/busybox
log() { echo "### $*"; }

log "page/kernel"
getconf PAGE_SIZE
uname -a

log "filesystems(erofs/ext4/f2fs/squashfs)"
cat /proc/filesystems | grep -Ei 'erofs|ext4|f2fs|squashfs|vfat'
echo "--- all ---"
cat /proc/filesystems

log "loop devices"
ls -l /dev/loop* 2>/dev/null
cat /proc/devices | grep -i loop
cat /proc/misc | grep -i loop 2>/dev/null

log "modules"
ls /lib/modules/ 2>/dev/null | head
ls /vendor/lib/modules/ 2>/dev/null | head -30

log "busybox mke2fs capabilities"
$BB mke2fs 2>&1 | head -3
$BB mkfs.ext4 2>&1 | head -3

log "loop+mke2fs+mount test (ext4)"
rm -rf "$LAB"; mkdir -p "$LAB/src/sub" "$LAB/mnt"
echo "hello-ext4-$(date +%s)" > "$LAB/src/hello.txt"
echo "nested" > "$LAB/src/sub/n.txt"
$BB mke2fs -q -t ext4 -d "$LAB/src" "$LAB/ext4.img" 16384 2>&1 | head -5
ls -l "$LAB/ext4.img"

log "mknod /dev/loop0"
mknod /dev/loop0 b 7 0 2>&1; ls -l /dev/loop0 2>&1
$BB losetup /dev/loop0 "$LAB/ext4.img" 2>&1
$BB losetup -a 2>&1
mount -t ext4 -o ro /dev/loop0 "$LAB/mnt" 2>&1
echo "mount rc=$?"
mount | grep "$LAB/mnt"
cat "$LAB/mnt/hello.txt" 2>&1
ls -lR "$LAB/mnt" 2>&1 | head -20
umount "$LAB/mnt" 2>&1
$BB losetup -d /dev/loop0 2>&1

log "direct mount -o loop (kernel auto loop)"
mount -t ext4 -o loop,ro "$LAB/ext4.img" "$LAB/mnt" 2>&1
echo "mount-loop rc=$?"
mount | grep "$LAB/mnt"
umount "$LAB/mnt" 2>&1

log "selinux"
getenforce
cat /proc/self/attr/current 2>/dev/null
echo "context=$(id -Z 2>/dev/null)"

log "tool availability in su PATH"
echo "PATH=$PATH"
which mkfs.erofs mke2fs e2fsdroid lpmake lpunpack simg2img 2>&1

log "done"
