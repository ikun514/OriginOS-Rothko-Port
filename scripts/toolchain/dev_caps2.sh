#!/system/bin/sh
# dev_caps2.sh -- 第二轮设备能力探测：zstd / 内核 erofs 压缩支持 / 完整 mkfs.erofs 选项
echo "=== device ==="
getprop ro.product.device; getprop ro.build.version.release; uname -r; getenforce

echo "=== mkfs.erofs version / compressors ==="
mkfs.erofs --version 2>&1 | head -5
echo "--- try zstd ---"
mkfs.erofs -zzstd,level=9 /data/local/tmp/lab/zstd_probe.erofs /data/local/tmp/lab/src 2>&1 | head -5
ls -l /data/local/tmp/lab/zstd_probe.erofs 2>&1
echo "--- try lzma ---"
mkfs.erofs -zlzma,level=9 /data/local/tmp/lab/lzma_probe.erofs /data/local/tmp/lab/src 2>&1 | head -5
echo "--- try deflate ---"
mkfs.erofs -zdeflate,level=9 /data/local/tmp/lab/deflate_probe.erofs /data/local/tmp/lab/src 2>&1 | head -5

echo "=== mkfs.erofs 完整扩展选项 (-E) ==="
mkfs.erofs --help 2>&1 | sed -n '40,120p'

echo "=== 内核 erofs 压缩支持 (kallsyms) ==="
grep -iE "erofs.*(zstd|lzma|deflate|lz4)|z_erofs_(zstd|lzma|deflate|lz4)" /proc/kallsyms 2>/dev/null | head -20
echo "--- 全部 erofs 符号数 ---"
grep -c -i erofs /proc/kallsyms 2>/dev/null
echo "--- zstd 相关符号数 ---"
grep -c -i zstd /proc/kallsyms 2>/dev/null
echo "--- kptr_restrict ---"
cat /proc/sys/kernel/kptr_restrict 2>/dev/null

echo "=== 内核 config (如果有) ==="
ls /proc/config.gz 2>/dev/null && zcat /proc/config.gz 2>/dev/null | grep -i "EROFS" | head -20

echo "=== fsck.erofs / dump.erofs 选项 ==="
fsck.erofs --help 2>&1 | head -30
echo "---"
dump.erofs --help 2>&1 | head -20
echo "=== done ==="
