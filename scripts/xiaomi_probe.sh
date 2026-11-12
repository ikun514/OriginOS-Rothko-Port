#!/system/bin/sh
echo "===== VINTF manifests in /vendor/etc/vintf ====="
ls /vendor/etc/vintf/manifest/ 2>/dev/null | sed 's/android\.hardware\.//;s/\.xml$//' | sort | tr '\n' ' '
echo
echo "===== VINTF manifests in /odm/etc/vintf ====="
ls /odm/etc/vintf/manifest/ 2>/dev/null | sed 's/android\.hardware\.//;s/\.xml$//' | sort | tr '\n' ' '
echo
echo "===== HAL impls /vendor/lib64/hw (count) ====="
ls /vendor/lib64/hw 2>/dev/null | wc -l
ls /vendor/lib64/hw 2>/dev/null | grep -E '@(1|2|3|4)' | sed 's/\.so$//' | head -60 | tr '\n' ' '
echo
echo "===== /vendor/etc/init rc list ====="
ls /vendor/etc/init/ 2>/dev/null | tr '\n' ' '
echo
echo "===== /vendor top-level ====="
ls /vendor
echo "===== /odm top-level + size ====="
ls /odm
du -sh /odm /vendor /product /system_ext /system /mi_ext 2>/dev/null
echo "===== odm/etc ====="
ls /odm/etc
echo "===== camera/sensor/touch related files ====="
ls /odm/firmware 2>/dev/null | head -20
ls /odm/etc/camera 2>/dev/null | head -20
echo "===== /vendor/firmware count ====="
ls /vendor/firmware 2>/dev/null | wc -l
echo "===== modules dir ====="
ls /vendor/lib/modules 2>/dev/null | head -5
echo "===== vendor props ====="
getprop | grep -E '^\[(ro\.vendor\.(api|build|product|mediatek|mtk|display|audio|camera|hardware)|ro\.hardware|ro\.boot\.(hardware|verifiedbootstate|veritymode))' | head -40
