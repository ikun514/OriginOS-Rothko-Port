#!/system/bin/sh
# dev_lib.sh -- 设备端公共函数库（source 使用）
# 约定：只读写 /data/local/tmp 下的临时目录，不触碰任何真实分区。

MKFS_EROFS=${MKFS_EROFS:-/system/bin/mkfs.erofs}
MKE2FS=${MKE2FS:-/system/bin/mke2fs}
E2FSDROID=${E2FSDROID:-/system/bin/e2fsdroid}
FSCK_EROFS=${FSCK_EROFS:-/system/bin/fsck.erofs}
DUMP_EROFS=${DUMP_EROFS:-/system/bin/dump.erofs}
DUMP_LP=${DUMP_LP:-/system/bin/lpdump}

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "FATAL: $*" >&2; exit 1; }

# 找一个空闲 loop 设备（toybox losetup -f 可能按需创建设备节点）
find_free_loop() {
    i=0
    while [ $i -lt 12 ]; do
        L=$(losetup -f 2>/dev/null)
        if [ -n "$L" ] && [ -b "$L" ]; then
            echo "$L"
            return 0
        fi
        i=$((i + 1))
        sleep 0.2
    done
    return 1
}

# 让内核 loop 线程(u:r:kernel:s0)能读取镜像文件：
# /data/local/tmp 下文件默认 shell_data_file，会被 SELinux 拒绝 read -> mount EIO
# 改成 system_file（kernel 域有 read 权限），挂载后由调用方 restore_image_label 恢复。
set_image_label() { chcon u:object_r:system_file:s0 "$1" 2>/dev/null; }
restore_image_label() { chcon u:object_r:shell_data_file:s0 "$1" 2>/dev/null; }

# attach_loop IMG -> 输出 loop 设备路径（失败返回非 0）
attach_loop() {
    img=$1
    i=0
    while [ $i -lt 8 ]; do
        L=$(find_free_loop) || return 1
        if losetup "$L" "$img" 2>/dev/null; then
            echo "$L"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

detach_loop() { [ -n "$1" ] && losetup -d "$1" 2>/dev/null; }

# mount_image IMG FSTYPE MNT -> 0/1 (自动 chcon + loop + mount)
mount_image() {
    img=$1; fstype=$2; mnt=$3
    mkdir -p "$mnt"
    set_image_label "$img"
    L=$(attach_loop "$img") || { log "attach_loop failed for $img"; return 1; }
    MOUNTED_LOOP=$L
    if mount -t "$fstype" -o ro "$L" "$mnt"; then
        log "mounted $img on $mnt via $L ($fstype)"
        return 0
    fi
    log "mount -t $fstype $L $mnt failed (dmesg: $(dmesg 2>/dev/null | grep -iE 'avc|erofs|ext4' | tail -2 | tr '\n' ' '))"
    detach_loop "$L"
    MOUNTED_LOOP=
    return 1
}

unmount_image() { [ -n "$1" ] && umount "$1" 2>/dev/null; detach_loop "$MOUNTED_LOOP"; MOUNTED_LOOP=; }

# tree_sha256 DIR -> 排序后的 "sha256  ./relpath" 列表
tree_sha256() {
    ( cd "$1" && find . \( -type f -o -type l \) -print0 2>/dev/null |
        while IFS= read -r -d '' f; do
            if [ -L "$f" ]; then
                printf 'LINK %s -> %s\n' "$f" "$(readlink "$f")"
            else
                sha256sum "$f"
            fi
        done ) | sort -k2
}
