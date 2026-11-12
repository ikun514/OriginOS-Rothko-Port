#!/system/bin/sh
echo "===== gallery state ====="
ps -A -o PID,NAME 2>/dev/null | grep -i gallery
dumpsys activity activities 2>/dev/null | grep -E "topResumedActivity=" | head -2
echo "max_map_count=$(cat /proc/sys/vm/max_map_count)"
echo
echo "===== gallery crash since (logcat crash buffer) ====="
logcat -d -b crash -t 60 2>/dev/null | grep -iE "gallery|Fatal|Abort" | tail -10
echo
echo "===== BT dump (scan/discovery) ====="
dumpsys bluetooth_manager 2>/dev/null > /data/local/tmp/bt_dump.txt
grep -iE "scan|discovery|Discover|Ble|advertis" /data/local/tmp/bt_dump.txt | head -30
echo "--- state ---"
grep -iE "^  enabled|^  state|mEnable|Bluetooth crashed|Ble app registered" /data/local/tmp/bt_dump.txt | head -10
echo
echo "===== BT logcat ====="
logcat -d -b all -t 4000 2>/dev/null | grep -iE "bluetooth|btif|bt_stack|hci|gatt|scan" | tail -40
echo
echo "===== BT kernel ====="
dmesg 2>/dev/null | grep -iE "bluetooth|bt_|conninfra|mtk_bt|wmt" | tail -20
echo "rfkill:"
ls /sys/class/bluetooth 2>/dev/null
cat /proc/net/bluetooth 2>/dev/null | head -5
echo
echo "===== status bar height info ====="
dumpsys window displays 2>/dev/null | grep -iE "statusBars|insets" | head -5
getprop | grep -iE "statusbar|status_bar" | head -10
echo DONE
