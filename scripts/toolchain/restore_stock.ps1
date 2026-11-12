param(
    [ValidateSet('prepare', 'verify', 'stream')][string]$Mode = 'prepare',
    [string]$StageDir = '/sdcard/work/rollback',
    [switch]$RebootRecovery,
    [switch]$SkipLocalHash,
    [switch]$ConfirmWrite,
    [string]$Manifest = ''
)
# restore_stock.ps1 -- one-click rollback to STOCK rothko super + vendor_boot.
#   prepare : verify local files, push images + rollback_stock.sh to $StageDir, verify sha256 on device, print recovery steps
#   verify  : (after reboot to Android) read partitions back via su and compare sha256 with manifest
#   stream  : fallback - write partition directly from PC stdin (adb shell dd < image). Run in RECOVERY only; needs -ConfirmWrite
# NOTE: keep this file ASCII-only (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$adb = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$proj = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$rbdir = Join-Path $proj 'scripts\toolchain\rollback'
if (-not $Manifest) { $Manifest = Join-Path $rbdir 'stock_manifest.json' }
$log = Join-Path $proj '06_logs\restore_stock.log'

function L([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $m"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}
Set-Content -Path $log -Value "=== restore_stock mode=$Mode $(Get-Date -Format o) ===" -Encoding UTF8

if (-not (Test-Path $Manifest)) { throw "manifest not found: $Manifest" }
$man = Get-Content $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$files = $man.files
L "manifest: $Manifest ($($files.Count) files)"

function Get-AdbDevice([string]$want = 'device') {
    $lines = & $adb devices 2>&1
    $devs = @()
    foreach ($ln in $lines) {
        if ($ln -match '^(\S+)\s+(device|recovery|sideload|bootloader)\s*$') {
            $devs += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    }
    if (-not $devs) { return $null }
    if ($want -eq 'any') { return ($devs | Select-Object -First 1) }
    return ($devs | Where-Object { $_.State -eq $want } | Select-Object -First 1)
}

function Get-RemoteSha([string]$dev, [int64]$size, [int]$bs = 4MB) {
    $count = [int64]($size / $bs)
    $cmd = "dd if=$dev bs=$([int]($bs / 1MB))M count=$count 2>/dev/null | sha256sum"
    $out = & $adb shell su -c $cmd 2>&1
    $line = ($out | Where-Object { $_ -match '^[0-9a-f]{64}' } | Select-Object -First 1)
    if (-not $line) { return $null }
    return ($line -split '\s+')[0]
}

# ---------------------------------------------------------------- prepare
if ($Mode -eq 'prepare') {
    L "1) verify local file hashes (super is 9GB, ~35s)"
    foreach ($f in $files) {
        $p = Join-Path $proj ($f.local_path -replace '/', '\')
        if (-not (Test-Path $p)) { throw "missing local file: $p" }
        $sz = (Get-Item $p).Length
        if ($sz -ne $f.size) { throw "$p size $sz != manifest $($f.size)" }
        if ($SkipLocalHash) { L "   [skip-hash] $($f.name) $sz bytes"; continue }
        $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
        $ok = $h -eq $f.sha256
        L ("   {0,-34} {1,14:N0} B  sha256={2}  {3}" -f $f.name, $sz, $h, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
        if (-not $ok) { throw "local sha256 mismatch for $($f.name): expected $($f.sha256)" }
    }

    L "2) adb device check"
    $d = Get-AdbDevice 'device'
    if (-not $d) {
        $d2 = Get-AdbDevice 'any'
        if ($d2) { L "   device state is '$($d2.State)' ($($d2.Serial)). -Mode prepare requires ANDROID (state=device) because it pushes files via /sdcard." }
        L "   If you are already in recovery, use:  -Mode stream -ConfirmWrite   (writes directly from PC, no staging)"
        throw "prepare needs the device in ANDROID mode"
    }
    L "   $($d.Serial) state=$($d.State)"

    L "   2b) /sdcard free space check (need ~10.5 GB)"
    $df = & $adb shell "df -k /sdcard" 2>&1
    $dfLine = ($df | Select-Object -Last 1)
    L "   $dfLine"
    if ($dfLine -match '\s(\d+)\s+\d+%\s') {
        $availKb = [int64]$Matches[1]
        if ($availKb -lt 11000000) { throw "not enough free space in /sdcard: $([math]::Round($availKb/1MB)) MB (need ~10.5 GB)" }
    }

    L "2c) re-use already staged files if hash matches (avoid re-pushing 9 GB)"
    & $adb shell "mkdir -p $StageDir" 2>&1 | Out-Null
    $needPush = @{}
    foreach ($f in $files) {
        $remote = "$StageDir/$($f.name)"
        $rsz = & $adb shell "stat -c %s '$remote' 2>/dev/null" 2>&1
        $needPush[$f.name] = $true
        if ($rsz -match '^\d+$' -and [int64]$rsz -eq $f.size) {
            $h = & $adb shell "su -c 'sha256sum $remote'" 2>&1 | Where-Object { $_ -match '^[0-9a-f]{64}' } | Select-Object -First 1
            $h = if ($h) { ($h -split '\s+')[0] } else { '' }
            if ($h -eq $f.sha256) { $needPush[$f.name] = $false; L "   already staged+verified: $($f.name)" }
        }
    }

    L "3) push files to $StageDir"
    foreach ($f in $files) {
        if ($needPush[$f.name] -eq $false) { continue }
        $p = Join-Path $proj ($f.local_path -replace '/', '\')
        $remote = "$StageDir/$($f.name)"
        # remove stale/partial file before pushing
        & $adb shell "rm -f '$remote'" 2>&1 | Out-Null
        $t0 = Get-Date
        & $adb push $p $remote 2>&1 | ForEach-Object { L "   push: $_" }
        L ("   pushed {0} in {1:N1}s" -f $f.name, ((Get-Date) - $t0).TotalSeconds)
    }
    & $adb push (Join-Path $rbdir 'rollback_stock.sh') "$StageDir/rollback_stock.sh" 2>&1 | ForEach-Object { L "   push: $_" }
    & $adb push $Manifest "$StageDir/stock_manifest.json" 2>&1 | ForEach-Object { L "   push: $_" }
    $legacyFlash = Join-Path $proj 'scripts\flash_part.sh'
    if (Test-Path $legacyFlash) {
        & $adb push $legacyFlash "$StageDir/flash_part.sh" 2>&1 | ForEach-Object { L "   push: $_" }
    }
    & $adb shell "cd $StageDir; for f in *.sh; do sed -i 's/\r$//' \$f; chmod 755 \$f; done; ls -l" 2>&1 | ForEach-Object { L "   $_" }

    L "4) verify staged images on device (sha256)"
    $allOk = $true
    foreach ($f in $files) {
        $h = & $adb shell su -c "sha256sum $StageDir/$($f.name)" 2>&1 | Where-Object { $_ -match '^[0-9a-f]{64}' } | Select-Object -First 1
        $h = if ($h) { ($h -split '\s+')[0] } else { '' }
        $ok = ($h -eq $f.sha256)
        if (-not $ok) { $allOk = $false }
        L ("   {0,-34} device_sha256={1}  {2}" -f $f.name, $h, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
    }
    if (-not $allOk) { throw "device-side hash verify failed; re-push" }
    L "5) all staged files verified"

    L "================================================================"
    L "ROLLBACK READY. Next steps:"
    L "  1) adb reboot recovery   (OrangeFox)"
    L "  2) wait for recovery adb, then run:"
    L "     adb shell sh $StageDir/rollback_stock.sh"
    L "     (script: verify sha256 -> dd super -> dd vendor_boot_a -> sync -> full read-back verify -> reboot)"
    L "  3) after automatic reboot to Android, run:"
    L "     powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode verify"
    L "  NOTE: if /data is encrypted and /sdcard/work is not visible in recovery, use fallback:"
    L "     powershell -File $PSCommandPath -Mode stream -ConfirmWrite   (only in recovery)"
    L "================================================================"
    if ($RebootRecovery) {
        L "user asked -RebootRecovery: adb reboot recovery"
        & $adb reboot recovery 2>&1
    }
    exit 0
}

# ---------------------------------------------------------------- verify
if ($Mode -eq 'verify') {
    $d = Get-AdbDevice 'device'
    if (-not $d) { throw "no adb device in Android mode (need Android booted + adb)"; }
    L "   device $($d.Serial)"
    $allOk = $true
    foreach ($f in $files) {
        $h = Get-RemoteSha $f.target_dev $f.size
        $ok = ($h -eq $f.sha256)
        if (-not $ok) { $allOk = $false }
        L ("   {0,-24} {1}  expect={2}  {3}" -f $f.partition, $h, $f.sha256, $(if ($ok) { 'OK' } else { 'MISMATCH' }))
    }
    if ($allOk) { L "RESULT: PASS - device is back to STOCK" } else { L "RESULT: FAIL - see above" }
    exit $(if ($allOk) { 0 } else { 1 })
}

# ---------------------------------------------------------------- stream (fallback)
if ($Mode -eq 'stream') {
    if (-not $ConfirmWrite) { throw "refusing to write partitions without -ConfirmWrite (use only in recovery)" }
    $d = Get-AdbDevice
    if (-not $d) { throw "no adb device" }
    L "   device $($d.Serial) state=$($d.State)"
    if ($d.State -ne 'recovery' -and $d.State -ne 'sideload') {
        L "WARNING: device state is '$($d.State)', not recovery. Prefer recovery for partition writes."
    }
    $bootMode = & $adb shell getprop ro.boot.mode 2>&1
    $sysBoot = & $adb shell getprop sys.boot_completed 2>&1
    L "device boot mode=$bootMode sys.boot_completed=$sysBoot"
    if ($sysBoot -eq '1') { L "WARNING: device is booted to Android; streaming a whole partition is NOT safe here. Prefer recovery." }
    foreach ($f in $files) {
        $p = Join-Path $proj ($f.local_path -replace '/', '\')
        if (-not (Test-Path $p)) { throw "missing local file: $p" }
        L "streaming $($f.name) -> $($f.target_dev) ($([math]::Round($f.size/1GB,2)) GB)"
        $inner = "adb shell su -c `"dd of=$($f.target_dev) bs=4M conv=fsync`""
        $cmdLine = "cmd /c `"`"$adb`" shell su -c `"dd of=$($f.target_dev) bs=4M conv=fsync`" < `"$p`"`""
        $t0 = Get-Date
        cmd.exe /c $cmdLine 2>&1 | ForEach-Object { L "   $_" }
        L ("   streamed in {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds)
        $h = Get-RemoteSha $f.target_dev $f.size
        L ("   read-back {0}: {1}  {2}" -f $f.partition, $h, $(if ($h -eq $f.sha256) { 'OK' } else { 'MISMATCH' }))
    }
    exit 0
}
