#!/system/bin/sh
# KSU service.sh: late boot — skip OOBE + enable adb
mkdir -p /data/local/tmp 2>/dev/null
LOG=/data/portfix.log
{
  echo "==== $(date) service ===="
  settings put global development_settings_enabled 1 2>&1
  settings put global adb_enabled 1 2>&1
  settings put global setup_skipped 1 2>&1
  settings put secure user_setup_complete 1 2>&1
  settings put secure setup_wizard_has_run 1 2>&1
  settings put global device_provisioned 1 2>&1
  setprop persist.sys.usb.config adb,mtp 2>&1
  cmd package set-home-activity com.bbk.launcher2/.Launcher 2>&1
  pm disable-user --user 0 com.vivo.setupwizard 2>&1
  echo "adb_enabled=$(settings get global adb_enabled) setup_skipped=$(settings get global setup_skipped)"
  echo "==== service done ===="
} >> "$LOG" 2>&1
