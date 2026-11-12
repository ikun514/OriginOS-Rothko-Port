#!/system/bin/sh
# sizes in KB, sorted
show() {
  d="$1"; n="${2:-15}"
  echo "===== $d ====="
  du -sk "$d"/* 2>/dev/null | sort -n -r | head -"$n"
}
echo "===== / (system root) ====="
ls -la / | head -30
show / 20
show /vendor 20
show /odm 20
show /product 15
show /system_ext 15
show /mi_ext 10
echo "===== /vendor/lib64 du ====="
du -sk /vendor/lib64/hw 2>/dev/null
echo "===== odm/etc/camera size ====="
du -sk /odm/etc/camera /odm/etc/sensors /odm/etc/touch /odm/etc/disp0 /odm/etc/dqe 2>/dev/null
echo "===== fstab.mt6989 in vendor/etc vs vendor_boot ====="
md5sum /vendor/etc/fstab.mt6989 2>/dev/null
head -40 /vendor/etc/fstab.mt6989 2>/dev/null
