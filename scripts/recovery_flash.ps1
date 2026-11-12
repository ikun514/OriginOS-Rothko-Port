param(
  [Parameter(Mandatory=$true)][string]$DeviceImage,
  [Parameter(Mandatory=$true)][string]$Partition,
  [string]$LogFile = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\06_logs\recovery_flash.log',
  [switch]$SkipRebootRecovery
)
$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
function Log($m){ $t=Get-Date -Format 'HH:mm:ss'; "$t $m" | Tee-Object -FilePath $LogFile -Append | Write-Output }
function AdbDevices { (& $adb devices 2>&1) -join "`n" }

if (-not $SkipRebootRecovery) {
  Log "== reboot to recovery =="
  & $adb reboot recovery 2>&1 | Out-Null
}
$ok=$false
for ($i=0; $i -lt 90; $i++) {
  Start-Sleep -Seconds 2
  $d = AdbDevices
  if ($d -match 'device$' -or $d -match "`tdevice") {
    $mode = (& $adb shell "getprop ro.boot.mode; getprop ro.twrp.version; getprop ro.orangefox.version; getprop sys.boot_completed" 2>&1) -join '|'
    Log "device visible, props: $mode"
    if ($mode -match 'recovery' -or $mode -match 'twrp' -or $mode -match 'orangefox' -or $mode -match '^\|\|') { $ok=$true; break }
  }
}
if (-not $ok) {
  Log "!! adb not reachable in recovery after 180s (or not in recovery mode)"
  exit 2
}
Log "== recovery session OK, flashing =="
$cmd = "sh /data/local/tmp/flash_part.sh '$DeviceImage' '$Partition'"
Log "run: $cmd"
(& $adb shell $cmd 2>&1) | ForEach-Object { Log $_ }
Log "== flash done, rebooting =="
& $adb reboot 2>&1 | Out-Null
Log "DONE"
