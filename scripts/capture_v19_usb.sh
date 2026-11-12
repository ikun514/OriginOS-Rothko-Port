#!/system/bin/sh
echo "===== 1) pstore console: usb / vusbd / gadget ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'vusbd|usb|gadget|udc|configfs' | tail -60
echo
echo "===== 2) pstore: init service failures ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'cannot execve|Service .* (exited|failed)|Permission denied|avc: denied' | tail -40
echo
echo "===== 3) pstore: selinux state ====="
strings /sys/fs/pstore/console-ramoops-0 2>/dev/null | grep -iE 'SELinux|selinux|Enforcing|Permissive' | tail -20
echo
echo "===== 4) tombstones (names only) ====="
for f in /data/tombstones/tombstone_0?; do
  [ -f "$f" ] || continue
  echo "--- $f"
  head -8 "$f" 2>/dev/null
done
echo
echo "===== 5) pmsg ====="
strings /sys/fs/pstore/pmsg-ramoops-0 2>/dev/null | grep -iE 'usb|vusbd' | tail -20
echo
echo "===== 6) vivo logs about usb ====="
grep -rl -iE 'vusbd|UsbDeviceManager|usb' /data/vivo-common /data/vendor/bsplog 2>/dev/null | head -10
echo DONE
