#!/system/bin/sh
# Port boot automation (image level): auto-enable USB debugging + skip OOBE
# Runs from init at sys.boot_completed=1 in su domain (permissive).
LOG=/data/portfix_boot.log
{
  echo "== portfix_boot $(date) =="
  settings put global development_settings_enabled 1
  settings put global adb_enabled 1
  settings put global setup_skipped 1
  settings put secure user_setup_complete 1
  settings put secure setup_wizard_has_run 1
  settings put global device_provisioned 1
  setprop persist.sys.usb.config adb
  echo "adb_enabled=$(settings get global adb_enabled) development_settings_enabled=$(settings get global development_settings_enabled)"
  echo "setup_skipped=$(settings get global setup_skipped) user_setup_complete=$(settings get secure user_setup_complete) device_provisioned=$(settings get global device_provisioned)"
  echo "== portfix_boot done =="
} >> "$LOG" 2>&1
