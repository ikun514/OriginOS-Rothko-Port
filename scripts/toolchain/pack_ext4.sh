#!/system/bin/sh
# pack_ext4.sh -- 在手机上把目录打成 ext4 镜像
#
# 用法:
#   pack_ext4.sh SRC_DIR OUT_IMG SIZE_BYTES [options]
# options:
#   --label NAME            卷标
#   --mount-point /system   给 e2fsdroid 用的挂载点（默认 /）
#   --file-contexts FILE    SELinux file_contexts（默认 /system/etc/selinux/plat_file_contexts）
#   --fs-config FILE        fs_config（默认 /system/etc/selinux/plat_fs_config，存在才用）
#   --no-selinux            跳过 e2fsdroid（只 mke2fs -d）
#   --journal               保留 journal（默认 ^has_journal，与 Android 系统镜像一致）
#
# 流程（AOSP 同款）:
#   1) mke2fs -d 从目录建 ext4 并复制文件（含 uid/gid/mode/symlink）
#   2) e2fsdroid -e 对已填充的文件系统写入 SELinux xattr（只写 xattr，不重建文件）
# 注意: 不要给 e2fsdroid 传 -f src_dir（那是"从零建文件"模式，会报
#       "Ext2 directory already exists" 或 "Invalid argument while opening file"）。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

SRC=${1:-}; OUT=${2:-}; SIZE=${3:-}
[ -n "$SRC" ] && [ -n "$OUT" ] && [ -n "$SIZE" ] || die "usage: pack_ext4.sh SRC_DIR OUT_IMG SIZE_BYTES [options]"
shift 3 || true
[ -d "$SRC" ] || die "SRC not a directory: $SRC"

LABEL=
MOUNT_POINT=/
FILE_CONTEXTS=/system/etc/selinux/plat_file_contexts
FS_CONFIG=/system/etc/selinux/plat_fs_config
USE_SELINUX=1
JOURNAL=
while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL=$2; shift 2 ;;
        --mount-point) MOUNT_POINT=$2; shift 2 ;;
        --file-contexts) FILE_CONTEXTS=$2; shift 2 ;;
        --fs-config) FS_CONFIG=$2; shift 2 ;;
        --no-selinux) USE_SELINUX=0; shift ;;
        --journal) JOURNAL=1; shift ;;
        *) die "unknown option: $1" ;;
    esac
done

BLOCKS=$(( SIZE / 4096 ))
[ "$BLOCKS" -gt 0 ] || die "size too small: $SIZE"
[ -x "$MKE2FS" ] || die "mke2fs not found"
[ -x "$E2FSDROID" ] || die "e2fsdroid not found"

log "mke2fs -t ext4 -b 4096 -d $SRC $OUT ($BLOCKS blocks / $SIZE bytes)"
rm -f "$OUT"
OPTS="-q -t ext4 -b 4096 -I 256 -m 0 -d $SRC"
[ -z "$JOURNAL" ] && OPTS="$OPTS -O ^has_journal"
[ -n "$LABEL" ] && OPTS="$OPTS -L $LABEL"
# shellcheck disable=SC2086
$MKE2FS $OPTS "$OUT" "$BLOCKS" 2>&1 | head -8
rc=$?
[ -f "$OUT" ] || die "mke2fs failed rc=$rc"
log "mke2fs ok: $(ls -l "$OUT" | awk '{print $5}') bytes"

if [ "$USE_SELINUX" = "1" ] && [ -x "$E2FSDROID" ]; then
    if [ -f "$FILE_CONTEXTS" ]; then
        # -e：已有文件系统模式，只写 SELinux xattr
        FCARGS="-e -S $FILE_CONTEXTS -a $MOUNT_POINT"
        [ -f "$FS_CONFIG" ] && FCARGS="$FCARGS -C $FS_CONFIG"
        log "e2fsdroid $FCARGS $OUT"
        # shellcheck disable=SC2086
        e2out=$($E2FSDROID $FCARGS "$OUT" 2>&1)
        e2rc=$?
        echo "$e2out" | head -12
        log "e2fsdroid rc=$e2rc"
    else
        log "WARN: file_contexts not found: $FILE_CONTEXTS (skip e2fsdroid)"
    fi
fi

log "tune2fs -l summary"
tune2fs -l "$OUT" 2>/dev/null | grep -E "Filesystem volume name|Block count|Block size|Filesystem features|Inode size" | head -8
exit 0
