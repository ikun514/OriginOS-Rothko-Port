#!/system/bin/sh
# Build trimmed+repacked vivo system image on-device (LF line endings required).
W=/data/local/tmp/work
SRC=$W/tree/vivo_system
OUT=${1:-$W/out/vivo_system_lz4hc.img}
CTX=$W/cfg/system_etc_selinux/plat_file_contexts
TRIM=$W/trim_list.txt

if [ ! -d "$SRC/system" ]; then
  echo "ERROR: source tree missing: $SRC/system"
  exit 1
fi

if [ -f "$TRIM" ]; then
  echo "=== applying trim list ==="
  N=0
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      \#*) continue ;;
    esac
    if [ -e "$SRC$p" ]; then
      du -sk "$SRC$p" 2>/dev/null
      rm -rf "$SRC$p"
      N=$((N + 1))
    fi
  done < "$TRIM"
  echo "trimmed paths: $N"
else
  echo "no trim list"
fi

echo "=== tree size after trim ==="
du -sk "$SRC"

FCARGS=""
if [ -f "$CTX" ]; then
  echo "using file contexts: $CTX"
  FCARGS="--file-contexts=$CTX"
else
  echo "WARN: no plat_file_contexts, labels default"
fi

echo "=== mkfs.erofs lz4hc level=9 ==="
rm -f "$OUT"
time mkfs.erofs -zlz4hc,level=9 $FCARGS -T 0 "$OUT" "$SRC" 2>&1 | tail -6
ls -l "$OUT"

echo "=== mount verify ==="
mkdir -p $W/mnt2
chcon u:object_r:system_file:s0 "$OUT"
if mount -t erofs -o ro "$OUT" $W/mnt2; then
  echo "mount OK"
  ls $W/mnt2 | head -6
  ls $W/mnt2/system | head -6
  umount $W/mnt2
else
  echo "MOUNT FAILED"
fi
echo DONE
