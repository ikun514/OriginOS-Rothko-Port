#!/system/bin/sh
# Flash a raw image to a partition from recovery (OrangeFox) - size check + unmount + dd + readback verify
IMG="$1"
PART="$2"
if [ -z "$IMG" ] || [ -z "$PART" ]; then
  echo "usage: flash_part.sh <image> <partition-name|/dev/block/...>"
  exit 1
fi
if [ -b "$PART" ]; then DEV="$PART"; else DEV="/dev/block/by-name/$PART"; fi
if [ ! -b "$DEV" ]; then echo "ERROR: $DEV not a block device"; exit 1; fi
ISZ=$(stat -c %s "$IMG" 2>/dev/null || echo 0)
PSZ=$(blockdev --getsize64 "$DEV" 2>/dev/null || echo 0)
echo "image=$IMG size=$ISZ"
echo "device=$DEV size=$PSZ"
[ "$ISZ" -eq 0 ] && { echo "ERROR: bad image"; exit 1; }
[ "$ISZ" -gt "$PSZ" ] && { echo "ERROR: image larger than partition"; exit 1; }

# make sure nothing is mounted from logical partitions mapped on super
if [ "$PART" = "super" ]; then
  for m in /system /system_ext /vendor /product /odm /vendor_dlkm /system_dlkm /odm_dlkm /mi_ext /mnt/vendor/mi_ext; do
    grep -q " $m " /proc/mounts && umount -l "$m" 2>/dev/null && echo "unmounted $m"
  done
fi

echo "sha256(image): $(sha256sum "$IMG" | cut -d' ' -f1)"
echo "writing ..."
dd if="$IMG" of="$DEV" bs=4M conv=fsync 2>&1 | tail -2
sync
echo "read-back tail verify:"
dd if="$DEV" bs=1M skip=$(( (ISZ - 1048576) / 1048576 )) count=1 2>/dev/null | sha256sum | cut -d' ' -f1
dd if="$IMG" bs=1M skip=$(( (ISZ - 1048576) / 1048576 )) count=1 2>/dev/null | sha256sum | cut -d' ' -f1
echo FLASH_DONE
