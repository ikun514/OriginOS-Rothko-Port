#!/system/bin/sh
# roundtrip_erofs.sh -- 手机上完成 "目录 -> erofs 镜像 -> loop 挂载 -> 内容校验" 往返
#
# 用法:
#   roundtrip_erofs.sh SRC_TGZ WORKDIR OUT_IMG
# 说明:
#   SRC_TGZ  从 PC push 上来的 tar.gz（内含要打包的目录树）
#   WORKDIR  设备端工作目录（默认 /data/local/tmp/lab/roundtrip）
#   OUT_IMG  输出 erofs 镜像路径
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

TGZ=${1:?usage: roundtrip_erofs.sh SRC_TGZ WORKDIR OUT_IMG}
WORK=${2:-/data/local/tmp/lab/roundtrip}
OUT=${3:-$WORK/tree.erofs}
SRC=$WORK/src
MNT=$WORK/mnt

rm -rf "$WORK"
mkdir -p "$SRC" "$MNT"

log "== 1. 解包来源 tar.gz =="
ls -l "$TGZ"
tar -xzf "$TGZ" -C "$SRC" 2>&1 | head -5
[ $? -eq 0 ] || die "tar extract failed"
log "src files: $(find "$SRC" -type f | wc -l), dirs: $(find "$SRC" -type d | wc -l)"

log "== 2. 目录 -> erofs 镜像 (lz4hc, mount-point /system, file_contexts) =="
FC=/system/etc/selinux/plat_file_contexts
$HERE/pack_erofs.sh "$SRC" "$OUT" --compress lz4hc --mount-point /system \
    --file-contexts "$FC" --label system --timestamp 1700000000 2>&1
[ -f "$OUT" ] || die "pack_erofs failed"
OUT_SIZE=$(ls -l "$OUT" | awk '{print $5}')
log "erofs image size: $OUT_SIZE"

log "== 3. loop 挂载 (SELinux Enforcing, 仅给镜像文件改 label) =="
getenforce
mount_image "$OUT" erofs "$MNT" || die "mount erofs failed"
mount | grep -F "$MNT"

log "== 4. 内容校验: sha256 逐个文件比对 =="
tree_sha256 "$SRC" > "$WORK/src.sha256"
tree_sha256 "$MNT" > "$WORK/mnt.sha256"
wc -l < "$WORK/src.sha256" | xargs log "source entries:"
diff "$WORK/src.sha256" "$WORK/mnt.sha256" > "$WORK/diff.txt" 2>&1
DIFF_RC=$?
if [ $DIFF_RC -eq 0 ]; then
    log "CHECKSUMS_MATCH ($(wc -l < "$WORK/src.sha256") entries)"
else
    log "CHECKSUM_MISMATCH rc=$DIFF_RC"
    head -20 "$WORK/diff.txt"
fi
log "-- sample --"
head -5 "$WORK/src.sha256"
log "-- selinux labels in mounted image --"
ls -Z "$MNT" 2>&1 | head -8
log "-- symlink check --"
find "$MNT" -type l -exec ls -l {} \; 2>/dev/null | head -5

log "== 5. 卸载 + 恢复文件 label =="
unmount_image "$MNT"
mount | grep -cF "$MNT" | xargs log "remaining mounts on mnt:"
restore_image_label "$OUT"
losetup -a | grep -c loop | xargs log "attached loops:"

log "== 6. 写报告 =="
REPORT=$WORK/roundtrip_report.txt
{
    echo "=== EROFS ROUNDTRIP REPORT ==="
    echo "time: $(date)"
    echo "device: $(getprop ro.product.device) / $(getprop ro.build.version.release)"
    echo "kernel: $(uname -r)"
    echo "selinux: $(getenforce)"
    echo "mkfs.erofs: $($MKFS_EROFS --version 2>&1 | head -1)"
    echo "src_tgz: $TGZ"
    echo "src_entries: $(wc -l < "$WORK/src.sha256")"
    echo "image: $OUT"
    echo "image_size: $OUT_SIZE"
    echo "mount_fstype: erofs"
    echo "checksums_match: $([ $DIFF_RC -eq 0 ] && echo YES || echo NO)"
    echo "--- dump.erofs ---"
    $DUMP_EROFS "$OUT" 2>&1
    echo "--- src sha256 ---"
    cat "$WORK/src.sha256"
} > "$REPORT" 2>&1
log "report: $REPORT"
cat "$REPORT" | head -40
log "== DONE =="
