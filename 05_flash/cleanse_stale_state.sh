#!/system/bin/sh
B=/data/local/tmp/portfix/data_backup
mkdir -p $B
echo "=== before ==="
ls -l /data/misc/apexdata/com.android.permission/ /data/misc_de/0/apexdata/com.android.permission/ 2>&1
cp -a /data/misc/apexdata/com.android.permission/access.abx $B/access_misc.abx 2>/dev/null
cp -a /data/misc_de/0/apexdata/com.android.permission/access.abx $B/access_misc_de_0.abx 2>/dev/null
cp -a /data/system/appops_accesses.xml $B/appops_accesses.xml 2>/dev/null
echo "=== removing stale cross-brand state ==="
rm -f /data/misc/apexdata/com.android.permission/access.abx*
rm -f /data/misc_de/0/apexdata/com.android.permission/access.abx*
rm -f /data/system/appops_accesses.xml*
rm -rf /data/system/appops/discrete/* /data/system/appops/history/* 2>/dev/null
echo "=== after ==="
ls -l /data/misc/apexdata/com.android.permission/ /data/misc_de/0/apexdata/com.android.permission/ 2>&1
ls -l $B/
echo DONE
