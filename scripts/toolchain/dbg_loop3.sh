#!/system/bin/sh
echo "=== loop params ==="
cat /sys/module/loop/parameters/max_loop 2>&1
cat /sys/module/loop/parameters/max_part 2>&1
echo "=== sys/block loops ==="
ls /sys/block | grep -c loop
ls /sys/block | grep loop | tail -5
echo "=== losetup -a (full) ==="
losetup -a 2>&1
echo "=== toybox losetup usage ==="
losetup --help 2>&1 | head -20
echo "=== loop44/45/46 nodes ==="
ls -l /dev/block/loop44 /dev/block/loop45 /dev/block/loop46 2>&1
echo "=== dmesg loop ==="
dmesg 2>/dev/null | grep -iE 'loop|erofs' | tail -15
