param(
    [Parameter(Mandatory = $true)][string]$Script,          # 本地脚本（推到 /data/local/tmp/toolchain/）
    [string[]]$ScriptArgs = @(),                            # 传给脚本的参数
    [string[]]$PushFiles = @(),                             # 额外要 push 的本地文件
    [string]$PushTo = '/data/local/tmp/lab/input',          # 额外文件 push 到的设备目录
    [string]$PullPath = '',                                 # 要取回的设备端路径（文件或目录）
    [string]$PullTo = '',                                   # 取回到本地的路径
    [string]$Log = '',                                      # 日志文件（默认 06_logs/device_run_<script>.log）
    [switch]$NoRoot,                                        # 用 shell 身份跑（默认 su）
    [string[]]$ExtraScripts = @(),                          # 一并 push 的依赖脚本（如 dev_lib.sh）
    [int]$TimeoutSec = 600
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$adb = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$root = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$remoteDir = '/data/local/tmp/toolchain'

function Log-Line([string]$m) {
    $t = Get-Date -Format 'HH:mm:ss'
    $line = "$t $m"
    Write-Host $line
    if ($Log) { Add-Content -Path $Log -Value $line -Encoding UTF8 }
}

if (-not $Script -or -not (Test-Path $Script)) { throw "script not found: $Script" }
if (-not $Log) { $Log = Join-Path $root ("06_logs\device_run_" + [IO.Path]::GetFileNameWithoutExtension($Script) + ".log") }
$Log = $Log
Set-Content -Path $Log -Value "=== device_run $Script $(Get-Date -Format o) ===" -Encoding UTF8

$ver = & $adb shell getprop ro.product.device 2>&1
Log-Line "device=$ver"
& $adb shell "mkdir -p $remoteDir" | Out-Null

# 推送脚本
$all = @($Script) + $ExtraScripts
foreach ($f in $all) {
    if (-not (Test-Path $f)) { throw "file not found: $f" }
    $name = [IO.Path]::GetFileName($f)
    & $adb push $f "$remoteDir/$name" 2>&1 | ForEach-Object { Log-Line "push $_" }
    # Windows 换行 -> 去掉 CR，避免 sh 语法错误
    & $adb shell "sed -i 's/\r$//' $remoteDir/$name" 2>&1 | Out-Null
    & $adb shell "chmod 755 $remoteDir/$name" 2>&1 | Out-Null
}

# 额外数据文件
if ($PushFiles.Count -gt 0) {
    & $adb shell "mkdir -p $PushTo" | Out-Null
    foreach ($f in $PushFiles) {
        if (-not (Test-Path $f)) { throw "push file not found: $f" }
        $t0 = Get-Date
        & $adb push $f "$PushTo/" 2>&1 | ForEach-Object { Log-Line "push $_" }
        $sz = (Get-Item $f).Length
        Log-Line ("pushed {0} ({1:N0} bytes) in {2:N1}s" -f [IO.Path]::GetFileName($f), $sz, ((Get-Date) - $t0).TotalSeconds)
    }
}

# 组装命令
$name = [IO.Path]::GetFileName($Script)
$argStr = ($ScriptArgs | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '
$cmd = "sh $remoteDir/$name"
if ($argStr) { $cmd += " $argStr" }

Log-Line "--- run: $cmd ---"
$t0 = Get-Date
if ($NoRoot) {
    $out = & $adb shell $cmd 2>&1
} else {
    $out = & $adb shell su -c $cmd 2>&1
}
$rc = $LASTEXITCODE
$dur = ((Get-Date) - $t0).TotalSeconds
$out | ForEach-Object { Log-Line $_ }
Log-Line ("--- done rc=$rc in {0:N1}s ---" -f $dur)

if ($PullPath) {
    if (-not $PullTo) { $PullTo = Join-Path $root ('02_base\from_device\' + [IO.Path]::GetFileName($PullPath)) }
    $parent = Split-Path -Parent $PullTo
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    & $adb pull $PullPath $PullTo 2>&1 | ForEach-Object { Log-Line "pull $_" }
    if (Test-Path $PullTo) {
        if ((Get-Item $PullTo) -is [System.IO.DirectoryInfo]) {
            $files = Get-ChildItem $PullTo -Recurse -File
            Log-Line ("pulled dir {0}: {1} files, {2:N0} bytes" -f $PullTo, $files.Count, ($files | Measure-Object Length -Sum).Sum)
            $files | ForEach-Object { Log-Line ("  {0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.FullName) }
        } else {
            $h = (Get-FileHash $PullTo -Algorithm SHA256).Hash.ToLower()
            Log-Line ("pulled {0}: {1:N0} bytes sha256={2}" -f $PullTo, (Get-Item $PullTo).Length, $h)
        }
    }
}
exit $rc
