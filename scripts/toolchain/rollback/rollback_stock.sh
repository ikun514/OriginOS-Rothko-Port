#!/system/bin/sh
# rollback_stock.sh -- 在 recovery (OrangeFox) 内把 rothko 恢复成原厂 super + vendor_boot
#
# 用法（recovery 内）:
#   sh /sdcard/work/rollback/rollback_stock.sh [--no-reboot] [--both-slots]
#
# 流程: 定位镜像目录 -> 校验 sha256(与 manifest 一致) -> 检查分区容量
#       -> dd 写 super -> dd 写 vendor_boot 当前槽 -> sync
#       -> 整分区读回 sha256 对比 -> 打印 PASS/FAIL -> (默认) reboot
#
# 安全: 任何一步校验失败都立即退出，绝不写入。
set -u

SUPER_SHA=dc61e94414b3f8c7c998dc787e101437e2105a374dab683d9ca6c3ba9be9bdbd
VB_SHA=dd453a760bb6066264fafdf756aceba0ba659f4a1e2ca0673608a9cee255d0d3
SUPER_SIZE=9663676416
VB_SIZE=67108864

REBOOT=1
BOTH_SLOTS=0
for a in "$@"; do
    case "$a" in
        --no-reboot) REBOOT=0 ;;
        --both-slots) BOTH_SLOTS=1 ;;
        *) echo "unknown arg: $a"; exit 2 ;;
    esac
done

log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "!!! FATAL: $*"; exit 1; }

# ---------- 1. 定位镜像目录 ----------
CAND="/data/media/0/work/rollback"
if [ ! -d "$CAND" ]; then
    # 尝试挂载 userdata（recovery 可能未自动挂载 /data）
    log "try mounting /data ..."
    mount /data 2>/dev/null || mount -t f2fs /dev/block/by-name/userdata /data 2>/dev/null
    if [ -d "$CAND" ]; then
        log "mounted /data OK"
    fi
fi
if [ ! -d "$CAND" ]; then
    for c in /sdcard/work/rollback /data/media/0/work/rollback /tmp/rollback /storage/emulated/0/work/rollback; do
        if [ -f "$c/rollback_stock.sh" ] || [ -f "$c/rothko_current_super.img" ]; then
            CAND="$c"; break
        fi
    done
fi
[ -d "$CAND" ] || fail "rollback dir not found; /data may be encrypted/not mounted. push images again / check path"
DIR="$CAND"
SUPER_IMG="$DIR/rothko_current_super.img"
VB_IMG="$DIR/rothko_current_vendor_boot_a.img"
log "rollback dir: $DIR"
ls -l "$SUPER_IMG" "$VB_IMG" 2>/dev/null || fail "image files missing in $DIR"

# ---------- 2. sha256 预校验 ----------
have_sha256() { command -v sha256sum >/dev/null 2>&1; }
have_sha256 || fail "sha256sum not available in this recovery"

log "verifying super image sha256 (may take ~30-60s) ..."
S_SHA=$(sha256sum "$SUPER_IMG" | cut -d' ' -f1)
log "super sha256: $S_SHA"
[ "$S_SHA" = "$SUPER_SHA" ] || fail "super sha256 mismatch (expect $SUPER_SHA)"
log "verifying vendor_boot image sha256 ..."
V_SHA=$(sha256sum "$VB_IMG" | cut -d' ' -f1)
log "vendor_boot sha256: $V_SHA"
[ "$V_SHA" = "$VB_SHA" ] || fail "vendor_boot sha256 mismatch (expect $VB_SHA)"

# ---------- 3. 分区与容量检查 ----------
SUPER_DEV=/dev/block/by-name/super
[ -b "$SUPER_DEV" ] || fail "$SUPER_DEV not a block device"
SUPER_PSZ=$(blockdev --getsize64 "$SUPER_DEV" 2>/dev/null || echo 0)
log "super partition size: $SUPER_PSZ (image $SUPER_SIZE)"
[ "$SUPER_PSZ" -ge "$SUPER_SIZE" ] || fail "super partition smaller than image"

SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
[ -z "$SLOT" ] && SLOT=_a
VB_DEV="/dev/block/by-name/vendor_boot${SLOT}"
if [ ! -b "$VB_DEV" ]; then
    if [ -b /dev/block/by-name/vendor_boot ]; then VB_DEV=/dev/block/by-name/vendor_boot;
    else fail "vendor_boot device not found for slot $SLOT"; fi
fi
VB_PSZ=$(blockdev --getsize64 "$VB_DEV" 2>/dev/null || echo 0)
log "slot=$SLOT vendor_boot dev=$VB_DEV size=$VB_PSZ (image $VB_SIZE)"
[ "$VB_PSZ" -ge "$VB_SIZE" ] || fail "vendor_boot partition smaller than image"

# ---------- 4. 写入 ----------
log "writing super (2-4 min) ..."
dd if="$SUPER_IMG" of="$SUPER_DEV" bs=4M conv=fsync 2>&1 | tail -2 || fail "dd super failed"
log "writing vendor_boot $VB_DEV ..."
dd if="$VB_IMG" of="$VB_DEV" bs=4M conv=fsync 2>&1 | tail -2 || fail "dd vendor_boot failed"
if [ "$BOTH_SLOTS" = "1" ]; then
    for s in _a _b; do
        d=/dev/block/by-name/vendor_boot$s
        if [ -b "$d" ] && [ "$d" != "$VB_DEV" ]; then
            log "writing vendor_boot$s (both-slots) ..."
            dd if="$VB_IMG" of="$d" bs=4M conv=fsync 2>&1 | tail -1 || fail "dd vendor_boot$s failed"
        fi
    done
fi
sync

# ---------- 5. 读回校验 ----------
log "read-back verify super (1-2 min) ..."
RB_S=$(dd if="$SUPER_DEV" bs=4M count=$((SUPER_SIZE / 4194304)) 2>/dev/null | sha256sum | cut -d' ' -f1)
log " super read-back: $RB_S"
log "read-back verify vendor_boot ..."
RB_V=$(dd if="$VB_DEV" bs=1M count=$((VB_SIZE / 1048576)) 2>/dev/null | sha256sum | cut -d' ' -f1)
log " vendor_boot read-back: $RB_V"

RESULT=PASS
[ "$RB_S" = "$SUPER_SHA" ] || { RESULT=FAIL; log "SUPER MISMATCH!"; }
[ "$RB_V" = "$VB_SHA" ] || { RESULT=FAIL; log "VENDOR_BOOT MISMATCH!"; }

echo "=================================================="
echo "  ROLLBACK RESULT: $RESULT"
echo "  super:       $RB_S"
echo "  vendor_boot: $RB_V"
echo "=================================================="
# 尽力保存日志到可访问目录
{ echo "rollback $(date)"; echo "result=$RESULT"; echo "super=$RB_S"; echo "vendor_boot=$RB_V"; } > "$DIR/rollback_log.txt" 2>/dev/null

if [ "$RESULT" != "PASS" ]; then
    echo "!!! 校验失败，请勿重启，重新执行本脚本或改用 PC 端 -Stream 模式重刷"
    exit 1
fi
sync
if [ "$REBOOT" = "1" ]; then
    log "rebooting to Android ..."
    sleep 2
    reboot
else
    log "--no-reboot: 请手动重启"
fi
