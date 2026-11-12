#!/system/bin/sh
# evidence_collect.sh -- 汇总 task-2 工具链的所有设备端证据（可复现）
# 输出到 stdout，PC 侧保存为 06_logs/toolchain_evidence.log
set -u
. /data/local/tmp/toolchain/dev_lib.sh

echo "############################################################"
echo "# TOOLCHAIN EVIDENCE  $(date)"
echo "############################################################"

echo "=== [1] device ==="
echo "product: $(getprop ro.product.device)  build: $(getprop ro.build.display.id)"
echo "android: $(getprop ro.build.version.release)  kernel: $(uname -r)"
echo "selinux: $(getenforce)  page_size: $(getconf PAGE_SIZE)"

echo "=== [2] /system/bin tool versions ==="
printf "%-12s " mkfs.erofs; mkfs.erofs --version 2>&1 | head -1
printf "%-12s " mke2fs;    mke2fs -V 2>&1 | head -1
printf "%-12s " e2fsdroid; echo "(no --version; usage below)"; e2fsdroid -h 2>&1 | head -1
printf "%-12s " dump.erofs; dump.erofs --version 2>&1 | head -1
printf "%-12s " fsck.erofs; fsck.erofs --version 2>&1 | head -1
printf "%-12s " lpdump;    lpdump --version 2>&1 | head -1

echo "=== [3] zstd/lzma 不可用证据 ==="
mkfs.erofs -zzstd,level=9 /data/local/tmp/lab/z1.erofs /data/local/tmp/lab/src 2>&1 | head -3
mkfs.erofs -zlzma,level=9 /data/local/tmp/lab/z2.erofs /data/local/tmp/lab/src 2>&1 | head -3

echo "=== [4] 内核 EROFS 配置 ==="
zcat /proc/config.gz 2>/dev/null | grep -i "CONFIG_EROFS" 
echo "--- erofs 压缩相关内核符号 ---"
grep -iE "z_erofs_(lz4|zstd|lzma|deflate)" /proc/kallsyms 2>/dev/null | head

echo "=== [5] vendor_boot ramdisk 工具在 Android 用户空间的结果（备份方案） ==="
for b in mkfs.erofs mke2fs e2fsdroid dump.erofs; do
    echo "--- $b ---"
    out=$(LD_LIBRARY_PATH=/data/local/tmp/tools/lib64 /data/local/tmp/tools/bin/$b --version 2>&1)
    rc=$?
    echo "$out" | head -2
    echo "rc=$rc"
done

echo "=== [6] make_super.py 产物 lpdump 交叉验证 ==="
for f in /data/local/tmp/lab/lp_super_standard.img /data/local/tmp/lab/lp_super_mtk.img; do
    echo "--- $f ---"
    lpdump -s "$f" 2>&1 | head -12
    echo "lpdump rc=$?"
done

echo "=== [7] erofs 往返报告（PC 编排 roundtrip.ps1 产生） ==="
cat /data/local/tmp/lab/roundtrip/roundtrip_report.txt 2>/dev/null | head -30
echo "--- 完整报告与镜像已由 roundtrip.ps1 取回到 04_build/lab/from_device/ ---"

echo "=== [8] erofs 压缩率分析摘要（comp_analysis.sh 产生） ==="
cat /data/local/tmp/lab/comp/summary.txt 2>/dev/null

echo "=== [9] ext4 打包镜像 + 挂载 + 标签 ==="
IMG=/data/local/tmp/lab/ext4/system_ext4.img
ls -l "$IMG" 2>&1
tune2fs -l "$IMG" 2>/dev/null | grep -E "volume name|Block count|Block size|Filesystem features"
MNT=/data/local/tmp/lab/ext4/verify_mnt
mkdir -p "$MNT"
if mount_image "$IMG" ext4 "$MNT"; then
    echo "--- ls -Z (确认 e2fsdroid -e 写入的 SELinux xattr) ---"
    ls -Z "$MNT" 2>&1
    find "$MNT" -maxdepth 2 -type f 2>/dev/null | head -5 | while read -r f; do ls -Z "$f"; done
    cat "$MNT/hello.txt" 2>&1
    unmount_image "$MNT"
    restore_image_label "$IMG"
else
    echo "ext4 mount FAILED"
fi

echo "=== [10] 当前 loop/selinux 状态 ==="
losetup -a 2>&1 | wc -l
getenforce
echo "=== END ==="
