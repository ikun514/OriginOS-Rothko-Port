$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$log='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\06_logs\push_vivo.log'
function Log($m){ $t=Get-Date -Format 'HH:mm:ss'; "$t $m" | Tee-Object -FilePath $log -Append | Write-Output }
& $adb shell "mkdir -p /sdcard/work/images" 2>&1 | Out-Null
& $adb shell "ls -ld /sdcard/work /sdcard/work/images" 2>&1 | ForEach-Object { Log "  $_" }
$src='G:\OriginOS_Work\03_port\images'
$files=@('odm.img','odm_dlkm.img','system_dlkm.img','product.img','system_ext.img','vendor_dlkm.img','vendor.img','system.img')
foreach($f in $files){
  Log "push $f"
  & $adb push "$src\$f" "/sdcard/work/images/$f" 2>&1 | Select-Object -Last 1 | ForEach-Object { Log "  $_" }
}
Log "verify sizes on device (bytes)"
& $adb shell "ls -l /sdcard/work/images/" 2>&1 | ForEach-Object { Log "  $_" }
Log "DONE"
