#!/system/bin/sh
# Port boot automation (image level)
# 1) auto-enable USB debugging
# 2) skip OOBE flags
# 3) mount external storage (vold aborts once at boot on this port -> emulated volume stays unmounted)
LOG=/data/portfix_boot.log
{
  echo "== portfix_boot $(date) =="
  # --- feature 2: auto enable usb debugging ---
  settings put global development_settings_enabled 1
  settings put global adb_enabled 1
  setprop persist.sys.usb.config adb
  # --- feature 1: skip OOBE ---
  settings put global setup_skipped 1
  settings put secure user_setup_complete 1
  settings put secure setup_wizard_has_run 1
  settings put global device_provisioned 1
  echo "adb_enabled=$(settings get global adb_enabled) setup_skipped=$(settings get global setup_skipped)"

  # --- external storage workaround: vold crashes once at boot -> mount emulated volume and retry ---
  n=0
  while [ $n -lt 10 ]; do
    if [ -d /storage/emulated/0 ] && [ "$(ls -A /storage/emulated/0 2>/dev/null | head -1)" != "" ]; then
      echo "external_storage: already mounted (try $n)"
      break
    fi
    sm mount 'emulated;0' >/dev/null 2>&1
    sleep 5
    n=$((n+1))
  done
  echo "external_storage: $(sm list-volumes 2>/dev/null | tr '\n' ';')"
  ls -A /storage/emulated/0 2>/dev/null | head -5
  echo "== portfix_boot done =="
} >> "$LOG" 2>&1
