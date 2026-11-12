#!/system/bin/sh
echo "===== portfix logs ====="
for f in /data/portfix_early.log /data/portfix_boot.log; do
  echo "--- $f"
  cat $f 2>/dev/null | tail -30
done
echo "===== settings_global (adb/dev) ====="
grep -E 'adb_enabled|development_settings_enabled|setup_skipped|device_provisioned' /data/system/users/0/settings_global.xml 2>/dev/null
grep -E 'user_setup_complete|setup_wizard_has_run' /data/system/users/0/settings_secure.xml 2>/dev/null
echo "===== persistent props ====="
strings /data/property/persistent_properties 2>/dev/null | grep -iE 'usb|adb|zram' | head -10
echo "===== vivo log dirs ====="
for d in /data/vivo-common /data/vivo-others /data/vivodump; do echo "--- $d"; ls -l $d 2>/dev/null | head -8; done
echo "===== grep Settings crash in vivo logs ====="
grep -rl -iE 'com.android.settings|FATAL EXCEPTION' /data/vivo-common /data/vivodump /data/vendor 2>/dev/null | head -10
echo "===== vendor RIL / modem packages ====="
ls /data/vendor 2>/dev/null | head -20
echo "===== check radio props from pstore ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'ril-daemon|radio|telephony|modem' | tail -25
echo DONE
