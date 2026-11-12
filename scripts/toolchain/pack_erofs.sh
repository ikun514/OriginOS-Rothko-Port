#!/system/bin/sh
# pack_erofs.sh -- 在手机上把目录打成 EROFS 镜像（Android 系统镜像风格）
#
# 用法:
#   pack_erofs.sh SRC_DIR OUT_IMG [options]
# options:
#   --compress lz4hc|none      默认 lz4hc（level=9, cluster 16K）；none = 不压缩
#   --mount-point /system      镜像内挂载点，影响 --file-contexts 匹配与 fs 内前缀
#   --file-contexts FILE       SELinux file_contexts（如 /system/etc/selinux/plat_file_contexts）
#   --label NAME               卷标
#   --uuid UUID                固定 UUID
#   --timestamp N              固定构建时间戳
#   --all-root                 全部文件属主 root:root
#   --extra "FLAGS"            追加给 mkfs.erofs 的原始参数
#
# 例:
#   pack_erofs.sh /data/local/tmp/lab/src /data/local/tmp/lab/system.erofs \
#       --mount-point /system --file-contexts /system/etc/selinux/plat_file_contexts
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

SRC=${1:-}; OUT=${2:-}
[ -n "$SRC" ] && [ -n "$OUT" ] || die "usage: pack_erofs.sh SRC_DIR OUT_IMG [options]"
shift 2 || true
[ -d "$SRC" ] || die "SRC not a directory: $SRC"

COMPRESS=lz4hc
MOUNT_POINT=
FILE_CONTEXTS=
LABEL=
UUID=
TS=
ALLROOT=
EXTRA=
while [ $# -gt 0 ]; do
    case "$1" in
        --compress) COMPRESS=$2; shift 2 ;;
        --mount-point) MOUNT_POINT=$2; shift 2 ;;
        --file-contexts) FILE_CONTEXTS=$2; shift 2 ;;
        --label) LABEL=$2; shift 2 ;;
        --uuid) UUID=$2; shift 2 ;;
        --timestamp) TS=$2; shift 2 ;;
        --all-root) ALLROOT=1; shift ;;
        --extra) EXTRA=$2; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ -x "$MKFS_EROFS" ] || die "mkfs.erofs not found at $MKFS_EROFS"

OPTS="-d2"
[ -n "$TS" ] && OPTS="$OPTS -T $TS"
[ -n "$MOUNT_POINT" ] && OPTS="$OPTS --mount-point=$MOUNT_POINT"
[ -n "$FILE_CONTEXTS" ] && OPTS="$OPTS --file-contexts=$FILE_CONTEXTS"
[ -n "$LABEL" ] && OPTS="$OPTS -L $LABEL"
[ -n "$UUID" ] && OPTS="$OPTS -U $UUID"
[ -n "$ALLROOT" ] && OPTS="$OPTS --all-root"
while [ -n "$EXTRA" ]; do
    a=${EXTRA%% *}
    case "$EXTRA" in *" "*) EXTRA=${EXTRA#* } ;; *) EXTRA= ;; esac
    OPTS="$OPTS $a"
done
case "$COMPRESS" in
    none|"") ;;
    lz4) OPTS="$OPTS -zlz4" ;;
    lz4hc) OPTS="$OPTS -zlz4hc,level=9 -C16384" ;;
    *) OPTS="$OPTS -z$COMPRESS" ;;
esac

log "mkfs.erofs $OPTS $OUT $SRC"
rm -f "$OUT"
# shellcheck disable=SC2086
$MKFS_EROFS $OPTS "$OUT" "$SRC" 2>&1 | tail -8
rc=$?
[ -f "$OUT" ] || die "mkfs.erofs failed (no output)"
log "image: $(ls -l "$OUT" | awk '{print $5}') bytes"

log "fsck.erofs verify"
$FSCK_EROFS "$OUT" 2>&1 | tail -5
frc=$?
[ $frc -eq 0 ] || log "WARN: fsck.erofs rc=$frc (dmesg: $(dmesg | tail -2 | tr '\n' ' '))"

log "dump.erofs superblock"
$DUMP_EROFS "$OUT" 2>&1 | head -22
exit 0
