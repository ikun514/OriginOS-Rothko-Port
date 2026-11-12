#!/system/bin/sh
echo "===== /vendor size breakdown ====="
du -sh /vendor 2>/dev/null
du -sh /vendor/* 2>/dev/null | sort -hr | head -15
echo "===== /odm size breakdown ====="
du -sh /odm/* 2>/dev/null | sort -hr | head -15
echo "===== /odm/firmware ====="
du -sh /odm/firmware 2>/dev/null
echo "===== /odm/app + priv-app ====="
du -sh /odm/app /odm/priv-app 2>/dev/null
ls /odm/app 2>/dev/null | head
echo "===== /system top ====="
du -sh /system/* 2>/dev/null | sort -hr | head -20
echo "===== /product top ====="
du -sh /product/* 2>/dev/null | sort -hr | head -12
echo "===== /system_ext top ====="
du -sh /system_ext/* 2>/dev/null | sort -hr | head -12
echo "===== /mi_ext top ====="
du -sh /mi_ext/* 2>/dev/null | sort -hr | head -10
echo "===== erofs mount options ====="
mount | grep -E 'erofs' | head -5
echo "===== kernel erofs config hints ====="
ls /sys/module/erofs/parameters/ 2>/dev/null
cat /sys/module/erofs/parameters/* 2>/dev/null | head -10
echo "===== mi_ext references in vendor/etc ====="
grep -rl "mi_ext" /vendor/etc 2>/dev/null | head -10
grep -rl "mi_ext" /vendor/bin 2>/dev/null | head -5
