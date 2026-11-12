#!/system/bin/sh
echo "===== find setup wizard packages in vivo system ====="
mkdir -p /mnt/s /mnt/p
mount -t erofs -o ro /dev/block/mapper/system_a /mnt/s 2>&1; echo "system mount rc=$?"
mount -t erofs -o ro /dev/block/mapper/product_a /mnt/p 2>&1; echo "product mount rc=$?"
for d in /mnt/s/system/priv-app /mnt/s/system/app /mnt/p/product/priv-app /mnt/p/product/app /mnt/p/app /mnt/p/priv-app; do
  [ -d "$d" ] || continue
  echo "--- $d"
  ls "$d" | grep -iE 'setup|wizard|oobe|onboard|account|vivoacc' | head -20
done
echo "===== grep wizard activity names from manifests (strings) ====="
for f in $(ls -d /mnt/s/system/priv-app/*Setup* /mnt/s/system/app/*Setup* /mnt/p/product/priv-app/*Setup* /mnt/p/product/app/*Setup* 2>/dev/null); do
  echo "== $f"
  ls -l "$f"/*.apk 2>/dev/null | head -3
done
echo "===== vivo account related apks ====="
ls /mnt/s/system/priv-app /mnt/s/system/app 2>/dev/null | grep -iE 'vivo|bbk' | head -40
umount /mnt/s 2>/dev/null; umount /mnt/p 2>/dev/null
echo DONE
