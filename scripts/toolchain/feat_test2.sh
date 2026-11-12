#!/system/bin/sh
. /data/local/tmp/toolchain/dev_lib.sh
LAB=/data/local/tmp/lab
MNT=$LAB/mnt_feat2
mkdir -p "$MNT"
for combo in "fragments:-zlz4hc,level=9 -C16384 -Efragments" "dedupe:-zlz4hc,level=9 -C16384 -Ededupe"; do
  name=${combo%%:*}
  opts=${combo#*:}
  IMG=$LAB/featc_$name.erofs
  rm -f "$IMG"
  echo "=== compressed + $name ==="
  mkfs.erofs -d0 $opts "$IMG" $LAB/src 2>&1 | head -3
  echo "mkfs rc=$? size=$(stat -c %s "$IMG" 2>/dev/null)"
  dump.erofs -s "$IMG" 2>&1 | grep -E "features|compr_algs"
  if mount_image "$IMG" erofs "$MNT"; then
      echo "MOUNT OK"; ls "$MNT" | head -3; umount "$MNT"; detach_loop "$MOUNTED_LOOP"; MOUNTED_LOOP=
  else
      echo "MOUNT FAILED"
  fi
  restore_image_label "$IMG"
  dmesg 2>/dev/null | grep -i erofs | tail -2
done
