$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$root='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$img="$root\02_base\images"
$log="$root\06_logs\pull_logical.log"
function Log($m){ $t=Get-Date -Format 'HH:mm:ss'; "$t $m" | Tee-Object -FilePath $log -Append | Write-Output }
$parts = @('vendor','odm','vendor_dlkm','odm_dlkm','system_dlkm','mi_ext','system','system_ext')
foreach($p in $parts){
  $tgt = "$img\rothko_current_${p}_a.img"
  if(Test-Path $tgt){ $len=(Get-Item $tgt).Length; Log "skip $p (exists $len)"; continue }
  Log "== dd $p =="
  & $adb shell "su -c 'dd if=/dev/block/mapper/${p}_a of=/sdcard/_dump_${p}.img bs=4M 2>&1 | tail -1'" 2>&1 | ForEach-Object { Log "dd: $_" }
  & $adb shell "su -c 'blockdev --getsize64 /sdcard/_dump_${p}.img'" 2>&1 | ForEach-Object { Log "device size: $_" }
  & $adb pull "/sdcard/_dump_${p}.img" $tgt 2>&1 | Select-Object -Last 1 | ForEach-Object { Log "pull: $_" }
  Get-Item $tgt -ErrorAction SilentlyContinue | ForEach-Object { Log ("local size: " + $_.Length) }
  & $adb shell "su -c 'rm -f /sdcard/_dump_${p}.img'" | Out-Null
}
Log "DONE"
