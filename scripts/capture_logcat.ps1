$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$out='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\06_logs\v02_firstboot\logcat_stream.txt'
# wait for device
for($i=0;$i -lt 120;$i++){
  Start-Sleep -Seconds 2
  $d=(& $adb devices 2>&1) -join "`n"
  if($d -match '(?m)\t(device|recovery)\s*$'){ break }
}
"capture start $(Get-Date -Format HH:mm:ss)" | Out-File -Encoding utf8 $out
& $adb logcat -b all -v threadtime 2>&1 | Out-File -Encoding utf8 -Append $out
