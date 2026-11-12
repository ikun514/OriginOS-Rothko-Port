$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$root='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$img="$root\02_base\images"
$log="$root\06_logs\pull_base.log"
function Log($m){ $t=Get-Date -Format 'HH:mm:ss'; "$t $m" | Tee-Object -FilePath $log -Append | Write-Output }

Log "== dumping small partitions =="
foreach($p in 'boot_a','init_boot_a','vendor_boot_a','dtbo_a','vbmeta_a','vbmeta_system_a','vbmeta_vendor_a','misc','metadata'){
  & $adb shell "su -c 'dd if=/dev/block/by-name/$p of=/sdcard/_dump_$p.img bs=1M 2>/dev/null'" | Out-Null
  & $adb pull "/sdcard/_dump_$p.img" "$img\rothko_current_$p.img" 2>&1 | Select-Object -Last 1 | ForEach-Object { Log "pull $p : $_" }
  & $adb shell "su -c 'rm -f /sdcard/_dump_$p.img'" | Out-Null
}
Log "== super size =="
& $adb shell "su -c 'blockdev --getsize64 /dev/block/by-name/super'"
Log "== dumping super (dd to sdcard) =="
& $adb shell "su -c 'dd if=/dev/block/by-name/super of=/sdcard/_dump_super.img bs=16M 2>&1 | tail -2'"
& $adb shell "su -c 'sync; blockdev --getsize64 /sdcard/_dump_super.img'"
Log "== pulling super =="
& $adb pull "/sdcard/_dump_super.img" "$img\rothko_current_super.img" 2>&1 | Select-Object -Last 2 | ForEach-Object { Log "pull super: $_" }
Get-Item "$img\rothko_current_super.img" | ForEach-Object { Log ("super size on PC: " + $_.Length) }
& $adb shell "su -c 'rm -f /sdcard/_dump_super.img'" | Out-Null
Log "DONE"
