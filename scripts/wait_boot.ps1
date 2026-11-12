param(
  [int]$TimeoutSec = 420,
  [string]$LogFile = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\06_logs\wait_boot.log'
)
$ErrorActionPreference='Continue'
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
function Log($m){ $t=Get-Date -Format 'HH:mm:ss'; "$t $m" | Tee-Object -FilePath $LogFile -Append | Write-Output }
$seen=$false
$deadline=(Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  $devs = (& $adb devices 2>&1) -join "`n"
  if ($devs -match "device$" -or $devs -match "`tdevice") {
    if (-not $seen) { Log "adb device visible"; $seen=$true }
    $bc = (& $adb shell "getprop sys.boot_completed" 2>&1) -join '' 
    if ($bc -match '1') {
      Log "boot_completed=1"
      $fp = (& $adb shell "getprop ro.build.fingerprint; getprop ro.product.device; getprop ro.build.version.release; getprop ro.boot.slot_suffix" 2>&1) -join ' | '
      Log "props: $fp"
      exit 0
    }
  }
}
if ($seen) { Log "device visible but boot_completed never 1 (timeout $TimeoutSec s)" } else { Log "NO adb device within $TimeoutSec s" }
exit 1
