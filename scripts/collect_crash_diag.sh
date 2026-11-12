#!/system/bin/sh
D=/data/local/tmp/diag
mkdir -p $D
echo "=== mounts ==="
mount | grep -E ' /data | /metadata ' 
echo "=== dropbox list ==="
ls -l /data/system/dropbox 2>/dev/null | tail -20
echo "=== tombstones ==="
ls -l /data/tombstones 2>/dev/null | tail -10
echo "=== anr ==="
ls -l /data/anr 2>/dev/null | tail -10
echo "=== vivo log dirs ==="
ls -d /data/vivo* /data/log /data/vendor/vivo* /data/vendor/mtklog 2>/dev/null
echo "=== collect tarball ==="
tar czf $D/crash.tgz /data/system/dropbox /data/tombstones /data/anr 2>/dev/null
ls -l $D/crash.tgz
cp -f /sys/fs/pstore/console-ramoops-0 $D/pstore_console.txt 2>/dev/null
dmesg > $D/recovery_dmesg.txt 2>/dev/null
echo "=== pstore: modem/radio/baseband lines ==="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'modem|ccci|radio|mrdump|baseband|md1|md2|sim|ril' | head -40
echo "=== pstore: last crash/errors ==="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'panic|deadlock|Watchdog|FATAL|avc: denied|Service.*failed' | tail -20
ls -l $D
echo DONE
