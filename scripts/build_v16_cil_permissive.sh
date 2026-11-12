#!/system/bin/sh
# v16: image-level permissive: append (typepermissive T) for every type declared in CIL files.
# Uses existing v15 tree if present, else copies from flashed system_a.
B=/data/local/tmp/v16
mkdir -p $B
T=$B/tree
if [ -d /data/local/tmp/v15/tree/system ]; then
  echo "=== reuse v15 tree (cp -al hardlink) ==="
  rm -rf $T; mkdir -p $T
  cp -al /data/local/tmp/v15/tree/. $T/ 2>/dev/null || cp -a /data/local/tmp/v15/tree/. $T/
  echo "files=$(find $T -type f | wc -l)"
  cp -f /data/local/tmp/v15/plat_fc $B/plat_fc 2>/dev/null
else
  echo "=== copy from flashed system_a ==="
  mkdir -p $B/mnt
  mount -t erofs -o ro /dev/block/mapper/system_a $B/mnt || { echo "MOUNT FAIL"; exit 1; }
  cp -f $B/mnt/system/etc/selinux/plat_file_contexts $B/plat_fc
  rm -rf $T; mkdir -p $T
  cp -a $B/mnt/. $T/ 2>/dev/null
  echo "files=$(find $T -type f | wc -l)"
  umount $B/mnt 2>/dev/null
fi
[ -f $B/plat_fc ] || { echo "NO plat_fc"; exit 1; }

echo "=== collect type names from all visible partitions ==="
: > $B/types.txt
# system tree CILs
cat $T/system/etc/selinux/*.cil 2>/dev/null | grep -oE '\(type [a-zA-Z0-9_]+\)' | awk '{print $2}' | tr -d ')' >> $B/types.txt
# other partitions
for p in vendor_a odm_a system_ext_a product_a; do
  mkdir -p $B/m_$p
  mount -t erofs -o ro /dev/block/mapper/$p $B/m_$p 2>/dev/null || continue
  cat $B/m_$p/*/etc/selinux/*.cil $B/m_$p/etc/selinux/*.cil 2>/dev/null | grep -oE '\(type [a-zA-Z0-9_]+\)' | awk '{print $2}' | tr -d ')' >> $B/types.txt
  umount $B/m_$p 2>/dev/null
done
sort -u $B/types.txt > $B/types_u.txt
echo "unique types: $(wc -l < $B/types_u.txt)"
head -5 $B/types_u.txt

echo "=== append typepermissive to plat_sepolicy.cil ==="
CIL=$T/system/etc/selinux/plat_sepolicy.cil
cp -f $CIL $B/plat_sepolicy.cil.bak
{
  echo ""
  echo ";; ===== OriginOS port: force permissive for all declared types (image-level) ====="
  while IFS= read -r t; do
    [ -n "$t" ] && echo "(typepermissive $t)"
  done < $B/types_u.txt
} >> $CIL
echo "cil lines: $(wc -l < $CIL) (bak: $(wc -l < $B/plat_sepolicy.cil.bak))"
tail -4 $CIL

echo "=== repack ==="
rm -f $B/vivo_system_v16.img
mkfs.erofs -zlz4hc,level=9 --file-contexts=$B/plat_fc -T 0 $B/vivo_system_v16.img $T 2>&1 | tail -2
ls -l $B/vivo_system_v16.img
echo "=== verify ==="
mkdir -p $B/ver
mount -t erofs -o ro $B/vivo_system_v16.img $B/ver && { grep -c typepermissive $B/ver/system/etc/selinux/plat_sepolicy.cil; grep -c 'selinux/enforce' $B/ver/system/etc/init/hw/init.usb.rc; umount $B/ver; }
echo DONE
