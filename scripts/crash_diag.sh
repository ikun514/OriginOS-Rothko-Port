#!/system/bin/sh
T=$(ls -t /data/tombstones/tombstone_* 2>/dev/null | grep -v '\.pb' | head -1)
echo "latest tombstone: $T"
echo "=== header ==="
head -30 "$T" 2>/dev/null
echo "=== backtrace: first threads ==="
grep -n -A25 '^backtrace:' "$T" 2>/dev/null | head -60
echo "=== crash logcat ==="
logcat -b crash -d 2>/dev/null | tail -40
echo DONE
