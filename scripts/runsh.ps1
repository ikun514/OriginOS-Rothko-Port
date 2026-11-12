param([Parameter(Mandatory=$true)][string]$ScriptPath,[string[]]$ArgList)
$adb='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$tmp='/data/local/tmp/_run.sh'
& $adb push $ScriptPath $tmp | Out-Null
& $adb shell "su -c 'sh $tmp $($ArgList -join ' ')'"
