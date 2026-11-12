param(
    [string]$ImagesDir = '',
    [string]$PartsDir = 'G:\OriginOS_Work\02_base\lp_parts',
    [string]$Super = '',
    [string]$Out = 'G:\OriginOS_Work\02_base\super_v01_rothko_rebuild.img',
    [int64]$DeviceSize = 9663676416,
    [string]$Layout = 'mtk',
    [switch]$SkipBuild,
    [switch]$MetadataOnly
)
# rebuild_rothko_super.ps1 -- rebuild rothko super.img (v0.1 test image) from stock partition images, then self-verify.
# Inputs: 02_base\images\rothko_current_<name>.img if present, else extract from super.img into $PartsDir.
# NOTE: keep this file ASCII-only (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$proj = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$tc = Join-Path $proj 'scripts\toolchain'
$py = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
if (-not $ImagesDir) { $ImagesDir = Join-Path $proj '02_base\images' }
if (-not $Super) { $Super = Join-Path $ImagesDir 'rothko_current_super.img' }
$log = Join-Path $proj '06_logs\rebuild_super.log'

function L([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $m"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}
Set-Content -Path $log -Value "=== rebuild_rothko_super $(Get-Date -Format o) ===" -Encoding UTF8

# partition list: A-slot -> main_a, B-slot -> main_b
$parts = @('odm_a', 'odm_b', 'odm_dlkm_a', 'odm_dlkm_b', 'product_a', 'product_b', 'system_a', 'system_b',
    'system_dlkm_a', 'system_dlkm_b', 'system_ext_a', 'system_ext_b', 'vendor_a', 'vendor_b',
    'vendor_dlkm_a', 'vendor_dlkm_b', 'mi_ext_a', 'mi_ext_b')

# 1) prepare inputs
$missing = @()
foreach ($p in $parts) {
    if ($p -like '*_b') { continue }
    $inImages = Join-Path $ImagesDir "rothko_current_$p.img"
    $inParts = Join-Path $PartsDir "$p.img"
    if (-not (Test-Path $inImages) -and -not (Test-Path $inParts)) { $missing += $p }
}
if ($missing.Count -gt 0) {
    L "1) missing inputs [$($missing -join ',')] -> extracting from super into $PartsDir"
    New-Item -ItemType Directory -Force -Path $PartsDir | Out-Null
    & $py (Join-Path $tc 'lp_tool.py') unpack $Super -o $PartsDir --partitions ($missing -join ',') 2>&1 | ForEach-Object { L "   $_" }
}

$inputs = @{}
foreach ($p in $parts) {
    if ($p -like '*_b') { $inputs[$p] = '-'; continue }
    $inImages = Join-Path $ImagesDir "rothko_current_$p.img"
    $inParts = Join-Path $PartsDir "$p.img"
    if (Test-Path $inImages) { $inputs[$p] = (Resolve-Path $inImages).Path }
    elseif (Test-Path $inParts) { $inputs[$p] = (Resolve-Path $inParts).Path }
    else { throw "missing input for $p" }
}
foreach ($p in $parts) {
    if ($inputs[$p] -ne '-') {
        L ("   input {0,-16} {1,14:N0} B  {2}" -f $p, (Get-Item $inputs[$p]).Length, $inputs[$p])
    }
}

# 2) rebuild
if (-not $SkipBuild) {
    L "2) make_super.py -> $Out (layout=$Layout device_size=$DeviceSize metadata_only=$MetadataOnly)"
    $argList = @(
        (Join-Path $tc 'make_super.py'), '-o', $Out,
        '--device-size', "$DeviceSize", '--layout', $Layout,
        '--group', 'main_a:9653190656', '--group', 'main_b:9653190656'
    )
    if ($MetadataOnly) { $argList += '--metadata-only' }
    foreach ($p in $parts) {
        $g = if ($p -like '*_a') { 'main_a' } else { 'main_b' }
        $argList += '--partition'
        $argList += ("{0}:{1}:ro:{2}" -f $p, $g, $inputs[$p])
    }
    & $py @argList 2>&1 | ForEach-Object { L "   $_" }
}

# 3) self verify
L "3) verify_super.py"
& $py (Join-Path $tc 'verify_super.py') --built $Out --reference $Super --expect-size $DeviceSize 2>&1 | ForEach-Object { L "   $_" }
$rc = $LASTEXITCODE
L "verify_super rc=$rc"
if ($rc -ne 0) { throw "verify_super FAILED rc=$rc" }

# 4) summary
L "4) output"
if (Test-Path $Out) {
    $h = (Get-FileHash $Out -Algorithm SHA256).Hash.ToLower()
    L ("   {0}  {1:N0} bytes  sha256={2}" -f $Out, (Get-Item $Out).Length, $h)
}
L "=== DONE (log: $log) ==="
