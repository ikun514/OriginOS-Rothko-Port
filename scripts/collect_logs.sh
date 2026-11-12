#!/system/bin/sh
# Collect boot-failure diagnostics into /data/media/0/work/logs/<tag>/
TAG=${1:-$(date +%Y%m%d_%H%M%S)}
OUT=/data/media/0/work/logs/$TAG
mkdir -p "$OUT"
echo "collecting to $OUT"
# kernel / boot diagnostics
(cat /proc/last_kmsg 2>/dev/null || echo "no last_kmsg") > "$OUT/last_kmsg.txt"
dmesg > "$OUT/dmesg.txt" 2>/dev/null
cat /proc/cmdline > "$OUT/cmdline.txt" 2>/dev/null
# pstore (rammoops: console + pmsg + dmesg-ramoops)
if [ -d /sys/fs/pstore ]; then
  ls -la /sys/fs/pstore > "$OUT/pstore_list.txt" 2>/dev/null
  for f in /sys/fs/pstore/*; do
    [ -f "$f" ] && cat "$f" > "$OUT/pstore_$(basename "$f").txt" 2>/dev/null
  done
fi
# recovery logs
cp /tmp/recovery.log "$OUT/" 2>/dev/null
cp /tmp/last_log "$OUT/" 2>/dev/null
cp /cache/recovery/last_log "$OUT/" 2>/dev/null
# last boot logcat if present
cp /data/vendor/logs/* "$OUT/" 2>/dev/null
# mount / partitions info
cat /proc/mounts > "$OUT/mounts.txt" 2>/dev/null
ls -la /dev/block/mapper > "$OUT/mapper.txt" 2>/dev/null
blockdev --getsize64 /dev/block/by-name/super > "$OUT/super_size.txt" 2>/dev/null
echo "=== collected files ==="
ls -la "$OUT"
echo COLLECT_DONE
