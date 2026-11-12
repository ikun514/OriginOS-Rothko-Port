#!/system/bin/sh
# Diagnostic dump to /data (no adb needed): run by init service after boot_completed
D=/data/portfix_diag
mkdir -p $D
{
  echo "===== date ====="; date
  echo "===== getenforce ====="; getenforce
  echo "===== usb related props ====="
  getprop | grep -iE 'usb|adb|vusbd|boot_completed|vivo.market|debuggable' | head -80
  echo "===== sysfs usb ====="
  ls -l /sys/class/android_usb 2>&1 | head -5
  ls -l /config/usb_gadget 2>&1 | head -10
  cat /config/usb_gadget/g1/UDC 2>&1
  cat /config/usb_gadget/g1/functions/*/name 2>/dev/null | head
  echo "===== ps (usb related) ====="
  ps -A -o PID,PPID,USER,NAME 2>/dev/null | grep -iE 'vusbd|adbd|usbd|system_server|zygote' | head -20
  echo "===== init.svc states ====="
  getprop | grep -E 'init\.svc\.(adbd|vusbd|usbd|usb)' | head -20
  echo "===== dmesg tail (usb) ====="
  dmesg 2>/dev/null | grep -iE 'usb|udc|gadget|configfs' | tail -80
  echo "===== logcat tail (all buffers) ====="
  logcat -b all -d 2>/dev/null | grep -iE 'usb|adbd|vusbd|gadget' | tail -300
  echo "===== dumpsys usb ====="
  dumpsys usb 2>&1 | head -150
  echo "===== settings usb ====="
  settings get global adb_enabled 2>&1
  settings get global development_settings_enabled 2>&1
  settings list global 2>/dev/null | grep -iE 'usb|adb' | head -20
  echo "===== full logcat (last 2000 lines) ====="
  logcat -b all -d 2>/dev/null | tail -2000
} > $D/diag.txt 2>&1
echo "diag done $(date)" >> $D/diag.txt
# copy to /cache so recovery (which mounts /cache) can read it without /data decryption
cp -f $D/diag.txt /cache/portfix_diag.txt 2>/dev/null
chmod 644 /cache/portfix_diag.txt 2>/dev/null
