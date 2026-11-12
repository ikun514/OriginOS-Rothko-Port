#!/system/bin/sh
. /data/local/tmp/toolchain/dev_lib.sh
LAB=/data/local/tmp/lab
for opt in fragments dedupe ztailpacking; do
  IMG=$LAB/feat_$opt.erofs
  rm -f "$IMG"
  echo "=== -E$opt ==="
  mkfs.erofs -d0 -E$opt "$IMG" $LAB/src 2>&1 | head -3
  echo "mkfs rc=$? size=$(stat -c %s "$IMG" 2>/dev/null)"
  dump.erofs -s "$IMG" 2>&1 | grep -E "features|compr"
  MNT=$LAB/mnt_feat
  mkdir -p "$MNT"
  if mount_image "$IMG" erofs "$MNT"; then
      echo "MOUNT OK"; ls "$MNT" | head -3; umount "$MNT"; detach_loop "$MOUNTED_LOOP"; MOUNTED_LOOP=
  else
      echo "MOUNT FAILED (?????? feature)"
  fi
  restore_image_label "$IMG"
done
echo "=== dmesg ?? erofs ?? ==="
dmesg 2>/dev/null | grep -i erofs | tail -6
