#!/system/bin/sh
for T in $(ls -t /data/tombstones/tombstone_* 2>/dev/null | grep -v '\.pb' | head -8); do
  echo "=== $T ==="
  grep -m1 'Time:' "$T" 2>/dev/null
  grep -m1 'Cmdline:' "$T" 2>/dev/null
  grep -m1 -E 'signal ' "$T" 2>/dev/null
  grep -m1 'Abort message' "$T" 2>/dev/null | cut -c1-140
  grep -m1 -A3 '^backtrace:' "$T" 2>/dev/null | tail -3
done
echo DONE
