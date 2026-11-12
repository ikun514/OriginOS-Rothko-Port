#!/system/bin/sh
# comp_levels.sh -- 用 lz4hc level=9/12 重打包 rothko vendor_a / odm_a，测体积（Lead 任务 C）
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

WORK=/data/local/tmp/lab/comp
SUPER=/dev/block/by-name/super
mkdir -p "$WORK/extract" "$WORK/img"

# name:target_data(sectors):num_sectors(sectors) 来自 lp 元数据
for spec in vendor_a:14041088:3212320 odm_a:2048:1720816; do
    NAME=$(echo "$spec" | cut -d: -f1)
    TD=$(echo "$spec" | cut -d: -f2)
    NS=$(echo "$spec" | cut -d: -f3)
    IMG=$WORK/img/$NAME.img
    SRC=$WORK/extract/$NAME
    ORIG=$(stat -c %s "$IMG" 2>/dev/null || echo 0)
    if [ "$ORIG" = "0" ]; then
        echo "--- dd $NAME ---"
        dd if="$SUPER" of="$IMG" bs=512 skip=$TD count=$NS 2>&1 | tail -1
        ORIG=$(stat -c %s "$IMG")
    fi
    if [ ! -d "$SRC" ] || [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
        echo "--- extract $NAME -> $SRC ---"
        t0=$(date +%s)
        mkdir -p "$SRC"
        fsck.erofs --extract="$SRC" --overwrite "$IMG" 2>&1 | tail -2
        t1=$(date +%s)
        echo "extract_seconds=$((t1-t0))"
    fi
    FILES=$(find "$SRC" -type f | wc -l)
    UBYTES=$(find "$SRC" -type f -exec stat -c %s {} \; 2>/dev/null | awk '{s+=$1} END {print s+0}')
    echo "$NAME original_bytes=$ORIG uncompressed_bytes=$UBYTES files=$FILES" | tee -a "$WORK/summary_levels.txt"
    for lvl in 9 12; do
        OUT=$WORK/${NAME}_lz4hc${lvl}.erofs
        t0=$(date +%s)
        mkfs.erofs -d1 -zlz4hc,level=$lvl -C16384 -T 1700000000 --all-root "$OUT" "$SRC" 2>&1 | tail -1
        t1=$(date +%s)
        SZ=$(stat -c %s "$OUT" 2>/dev/null || echo 0)
        echo "$NAME lz4hc_level=$lvl repacked_bytes=$SZ vs_original=$(awk "BEGIN{printf \"%.4f\", $SZ/$ORIG}") reduction_pct=$(awk "BEGIN{printf \"%.2f\", (1-$SZ/$ORIG)*100}") seconds=$((t1-t0))" | tee -a "$WORK/summary_levels.txt"
    done
done
echo "=== summary_levels.txt ==="
cat "$WORK/summary_levels.txt"
