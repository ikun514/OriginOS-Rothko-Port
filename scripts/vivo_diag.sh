#!/system/bin/sh
echo "===== EVENTS (crash/died/boot_progress) ====="
logcat -b events -d 2>/dev/null | grep -E 'am_crash|am_proc_died|am_anr|am_kill|boot_progress|am_proc_start' | tail -50
echo "===== DMESG (zygote/system_server/oom/watchdog) ====="
dmesg 2>/dev/null | grep -iE 'zygote|system_server|watchdog|lowmemory|killed process|avc.*system_server' | tail -40
echo "===== MAIN LOG (SystemServer/AndroidRuntime/FATAL/WTF) ====="
logcat -b main -d 2>/dev/null | grep -E 'SystemServer|AndroidRuntime|FATAL|WTF|Exception|VintfObject|Binder' | tail -80
echo "===== MAIN LOG tail (non-auditd) ====="
logcat -b main -d 2>/dev/null | grep -v 'auditd' | tail -50
echo "===== INIT service states ====="
getprop | grep -E 'init\.svc\.(zygote|system_server|bootanim|surfaceflinger|adbd|vold)' 
echo "===== selinux ====="
getenforce
echo DONE
