#!/system/bin/sh
# comp_analysis.sh -- 在手机上分析现有 erofs 分区的压缩算法/压缩率，并做"解包->重打包"对比
# 全部本地 I/O（从 super 分区 dd 出镜像），不产生大流量 adb 传输；只读真实分区。
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/dev_lib.sh"

WORK=/data/local/tmp/lab/comp
SUPER=/dev/block/by-name/super
rm -rf "$WORK"; mkdir -p "$WORK/img" "$WORK/extract"

# 分区偏移(扇区)+大小(扇区) 来自 lp 元数据: name:target_data:num_sectors
PARTS="system_a:10475520:1718544 vendor_a:14041088:3212320 odm_a:2048:1720816"

echo "=== 1. 从 super 分区 dd 出分区镜像（本地，只读） ==="
for spec in $PARTS; do
    NAME=$(echo "$spec" | cut -d: -f1)
    TD=$(echo "$spec" | cut -d: -f2)
    NS=$(echo "$spec" | cut -d: -f3)
    IMG=$WORK/img/$NAME.img
    echo "--- dd $NAME: skip=$TD count=$NS sectors ---"
    dd if="$SUPER" of="$IMG" bs=512 skip=$TD count=$NS 2>&1 | tail -1
    ls -l "$IMG"
done

echo "=== 2. superblock / 压缩算法 ==="
for img in "$WORK"/img/*.img; do
    echo "--- $(basename "$img") ---"
    dump.erofs -s "$img" 2>&1 | grep -Ei "magic|blocksize|blocks:|inode|compr|feature|uuid|volume"
done

echo "=== 3. fsck.erofs -p: 全部文件的总压缩率 ==="
for img in "$WORK"/img/*.img; do
    echo "--- $(basename "$img") ---"
    fsck.erofs -p "$img" 2>&1 | tail -8
done

echo "=== 4. fsck.erofs --extract: 解出目录，统计未压缩体积 ==="
for name in odm_a system_a; do
    IMG=$WORK/img/$name.img
    OUT=$WORK/extract/$name
    mkdir -p "$OUT"
    echo "--- extract $name ---"
    t0=$(date +%s)
    fsck.erofs --extract="$OUT" --overwrite "$IMG" 2>&1 | tail -4
    t1=$(date +%s)
    echo "extract_seconds=$((t1-t0))"
    FILES=$(find "$OUT" -type f | wc -l)
    BYTES=$(find "$OUT" -type f -exec stat -c %s {} \; 2>/dev/null | awk '{s+=$1} END {print s+0}')
    echo "extracted_files=$FILES uncompressed_bytes=$BYTES"
    echo "$name uncompressed_bytes=$BYTES files=$FILES" >> "$WORK/summary.txt"
done

echo "=== 5. 重打包对比: 同一目录 lz4hc vs 原镜像 ==="
for name in odm_a system_a; do
    SRC=$WORK/extract/$name
    [ -d "$SRC" ] || continue
    ORIG=$(stat -c %s "$WORK/img/$name.img")
    for alg in lz4hc lz4; do
        OUTIMG=$WORK/${name}_$alg.erofs
        t0=$(date +%s)
        if [ "$alg" = "lz4hc" ]; then OPT="-zlz4hc,level=9 -C16384"; else OPT="-zlz4"; fi
        mkfs.erofs -d1 $OPT -T 1700000000 --all-root "$OUTIMG" "$SRC" 2>&1 | tail -2
        t1=$(date +%s)
        SZ=$(stat -c %s "$OUTIMG" 2>/dev/null || echo 0)
        echo "$name alg=$alg repacked_bytes=$SZ original_bytes=$ORIG ratio_vs_orig=$(awk "BEGIN{printf \"%.4f\", $SZ/$ORIG}") seconds=$((t1-t0))" | tee -a "$WORK/summary.txt"
    done
done

echo "=== 6. 挂载重打包镜像验证可读（lz4hc） ==="
for name in odm_a system_a; do
    IMG=$WORK/${name}_lz4hc.erofs
    [ -f "$IMG" ] || continue
    MNT=$WORK/mnt_$name
    if mount_image "$IMG" erofs "$MNT"; then
        echo "--- $name mounted OK ---"
        ls "$MNT" | head -8
        echo "--- sample read ---"
        find "$MNT" -type f 2>/dev/null | head -3 | while read -r f; do
            echo "  $f: $(stat -c %s "$f") bytes, sha256=$(sha256sum "$f" | cut -c1-16)"
        done
        echo "--- 与解包目录比对 3 个文件 ---"
        find "$MNT" -type f 2>/dev/null | head -3 | while read -r f; do
            rel=${f#$MNT}
            src=$WORK/extract/$name$rel
            if [ -f "$src" ]; then
                a=$(sha256sum "$f" | cut -d' ' -f1); b=$(sha256sum "$src" | cut -d' ' -f1)
                [ "$a" = "$b" ] && echo "  MATCH $rel" || echo "  MISMATCH $rel"
            fi
        done
        unmount_image "$MNT"
        restore_image_label "$IMG"
    else
        echo "--- $name MOUNT FAILED ---"
    fi
done

echo "=== 7. summary ==="
cat "$WORK/summary.txt" 2>/dev/null
echo "=== done ==="
