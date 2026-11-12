#!/system/bin/sh
echo "===== did init parse/reach portfix rc? ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'portfix|swapon|zram|swap' | head -20
echo "===== settings binary strings ====="
strings /data/system/users/0/settings_global.xml 2>/dev/null | grep -iE 'adb|develop|setup|provision' | head -20
strings /data/system/users/0/settings_secure.xml 2>/dev/null | grep -iE 'adb|setup|user_setup' | head -20
echo "===== circulatedlog files ====="
ls -l /data/vivo-common/circulatedlog 2>/dev/null | head
ls -l /data/vivo-common/dyn 2>/dev/null | head
echo "===== newest log-like files under /data (top 20 by mtime) ====="
find /data -maxdepth 3 -type f \( -name '*.log' -o -name '*.txt' -o -name '*log*' \) -newermt '2026-07-01 08:30' 2>/dev/null | head -20
echo "===== bbklog / vivo dump dirs ====="
for d in /data/vendor/bbklog /data/vendor/aee_exp /data/vendor/bsplog /data/vendor/diag; do echo "--- $d"; ls -l $d 2>/dev/null | head -6; done
echo "===== last_kmsg / dmesg pstore radio context ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'ccci|md_init|md1|modem.*fail|no service|SIM' | head -25
echo DONE
