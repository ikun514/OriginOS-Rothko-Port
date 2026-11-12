#!/system/bin/sh
# pull_vintf.sh -- 只读收集 vivo system 与 rothko vendor/odm 的 VINTF XML，打包到 /data/local/tmp 供 PC 拉取。
# 用 device_run.ps1 运行（避免 adb shell su -c 的内联引号问题）。
set -u
OUT=/data/local/tmp/vintf_pull
rm -rf "$OUT"
mkdir -p "$OUT"

# 1) vivo system（Lead 已解包的树）
V=/data/local/tmp/work/tree/vivo_system/system/etc/vintf
if [ -d "$V" ]; then
    tar -czf "$OUT/vivo_system_vintf.tgz" -C "$V" . 2>/dev/null
    echo "vivo_system: $(ls -l "$OUT/vivo_system_vintf.tgz" 2>/dev/null | awk '{print $5}') bytes, files=$(find "$V" -type f | wc -l)"
else
    echo "WARN: vivo vintf tree not found: $V"
fi

# 2) rothko 设备分区（vendor / odm / system_ext / system）
for p in vendor odm system_ext system; do
    SRC=/$p/etc/vintf
    if [ -d "$SRC" ]; then
        tar -czf "$OUT/rothko_${p}_vintf.tgz" -C "$SRC" . 2>/dev/null
        echo "rothko_${p}: $(ls -l "$OUT/rothko_${p}_vintf.tgz" 2>/dev/null | awk '{print $5}') bytes, files=$(find "$SRC" -type f | wc -l)"
    else
        echo "skip: $SRC not present"
    fi
done

ls -l "$OUT"
echo DONE
