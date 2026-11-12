param(
    [string]$VivoSystem = 'G:\OriginOS_Work\04_build\vivo_system_v03.img',
    [string]$Product = '',
    [string]$Vendor = '',
    [string]$SystemExt = '',
    [string]$Odm = '',
    [string]$MiExt = '',
    [string]$VendorDlkm = '',
    [string]$SystemDlkm = '',
    [string]$OdmDlkm = '',
    [string]$Out = 'G:\OriginOS_Work\04_build\v02_super.img',
    [int64]$DeviceSize = 9663676416,
    [int64]$GroupMainAMax = 9652142080,
    [int64]$FirstLogicalSector = 2048,
    [int64]$Alignment = 1048576,
    [switch]$IncludeEmptyBSlots,
    [switch]$SkipVerify,
    [switch]$DryRun,
    [switch]$Overwrite
)
# build_super_v02_checked.ps1 -- reviewed/hardened v0.2 super builder (offline; does not touch device).
# Fixes vs scripts\build_super_v02.ps1 (Lead):
#   1) exact 1MiB-align layout simulation (data_end / real padding / real margins, no 1MiB*9 guess)
#   2) checks $LASTEXITCODE after make_super.py / verify_super.py (native cmd failure does NOT throw in PS5.1)
#   3) refuses to "verify" a stale/0-byte output; checks final size == DeviceSize
#   4) consistent group max (built metadata uses the SAME GroupMainAMax as the budget check)
#   5) runs verify_super.py (LP checksums + non-overlap + bounds + fs magic) and writes a JSON manifest
# NOTE: ASCII-only file (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$proj = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$tc = Join-Path $proj 'scripts\toolchain'
$py = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$log = Join-Path $proj '06_logs\build_super_v02.log'
$manifestOut = Join-Path $proj '01_analysis\v02_super_manifest.json'

function L([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $m"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}
Set-Content -Path $log -Value "=== build_super_v02_checked $(Get-Date -Format o) ===" -Encoding UTF8

$vivo = 'G:\OriginOS_Work\03_port\images'
$base = Join-Path $proj '02_base\images'
if (-not $Product) { $Product = Join-Path $vivo 'product.img' }
if (-not $SystemExt) { $SystemExt = Join-Path $vivo 'system_ext.img' }
if (-not $Vendor) { $Vendor = Join-Path $base 'rothko_current_vendor_a.img' }
if (-not $Odm) { $Odm = Join-Path $base 'rothko_current_odm_a.img' }
if (-not $MiExt) { $MiExt = Join-Path $base 'rothko_current_mi_ext_a.img' }
if (-not $VendorDlkm) { $VendorDlkm = Join-Path $base 'rothko_current_vendor_dlkm_a.img' }
if (-not $SystemDlkm) { $SystemDlkm = Join-Path $base 'rothko_current_system_dlkm_a.img' }
if (-not $OdmDlkm) { $OdmDlkm = Join-Path $base 'rothko_current_odm_dlkm_a.img' }

# exact order required for v0.2
$order = @(
    @('product_a', $Product),
    @('vendor_a', $Vendor),
    @('system_ext_a', $SystemExt),
    @('odm_a', $Odm),
    @('system_a', $VivoSystem),
    @('mi_ext_a', $MiExt),
    @('vendor_dlkm_a', $VendorDlkm),
    @('system_dlkm_a', $SystemDlkm),
    @('odm_dlkm_a', $OdmDlkm)
)

L "1) inputs"
$sum = [int64]0
$items = @()
foreach ($o in $order) {
    $name = $o[0]; $path = $o[1]
    if (-not (Test-Path $path)) { throw "missing input image for $name : $path" }
    $len = (Get-Item $path).Length
    $sum += $len
    $items += [pscustomobject]@{ name = $name; path = $path; size = $len; mib = [math]::Round($len / 1MB, 2) }
    L ("   {0,-15} {1,14:N0} B  {2,10:N2} MiB  {3}" -f $name, $len, ($len / 1MB), $path)
}

L "2) exact 1MiB-align layout (same algorithm as make_super.py)"
$alignSectors = [int64]($Alignment / 512)
$cursor = [int64]$FirstLogicalSector
$layout = @()
foreach ($it in $items) {
    $cursor = [int64]([math]::Ceiling($cursor / $alignSectors) * $alignSectors)
    $nsec = [int64]([math]::Ceiling($it.size / 512.0))
    $startByte = $cursor * 512
    $layout += [pscustomobject]@{ name = $it.name; start = $startByte; size = $it.size; end = ($startByte + $it.size); sectors = $nsec }
    $cursor += $nsec
}
$dataEnd = $cursor * 512
$padBytes = $dataEnd - ($FirstLogicalSector * 512) - $sum
$freeDevice = $DeviceSize - $dataEnd
$freeGroup = $GroupMainAMax - $sum
$freeGroupEnd = $GroupMainAMax - $dataEnd
foreach ($l in $layout) {
    L ("   {0,-15} start={1,13:N0}  end={2,13:N0}  ({3,10:N2} MiB)" -f $l.name, $l.start, $l.end, ($l.size / 1MB))
}
L ("   sum(partitions) = {0:N0} B ({1:N2} GiB)" -f $sum, ($sum / 1GB))
L ("   data_end        = {0:N0} B ({1:N2} GiB)   (first_logical={2:N0}, align_padding={3:N0} B = {4:N2} MiB)" -f $dataEnd, ($dataEnd / 1GB), ($FirstLogicalSector * 512), $padBytes, ($padBytes / 1MB))
L ("   device_size     = {0:N0} B   free_after_data = {1:N0} B ({2:N2} MiB)" -f $DeviceSize, $freeDevice, ($freeDevice / 1MB))
L ("   group main_a max= {0:N0} B   free_vs_group(sum) = {1:N0} B ({2:N2} MiB)" -f $GroupMainAMax, $freeGroup, ($freeGroup / 1MB))
L ("   group main_a max= {0:N0} B   free_vs_group(data_end) = {1:N0} B ({2:N2} MiB)" -f $GroupMainAMax, $freeGroupEnd, ($freeGroupEnd / 1MB))

if ($freeGroup -lt 0) { throw "OVER BUDGET: sum exceeds group main_a max by $([math]::Abs($freeGroup)) B" }
if ($freeDevice -lt 0) { throw "OVER BUDGET: data_end exceeds device size by $([math]::Abs($freeDevice)) B" }
L "   budget: PASS"

$manifest = [ordered]@{
    generated_at = (Get-Date -Format o)
    layout       = 'mtk'
    device_size  = $DeviceSize
    group_main_a_max = $GroupMainAMax
    first_logical_sector = $FirstLogicalSector
    alignment    = $Alignment
    sum_partitions = $sum
    data_end     = $dataEnd
    free_after_data = $freeDevice
    free_vs_group = $freeGroup
    partitions   = @($layout | ForEach-Object { [ordered]@{ name = $_.name; start = $_.start; end = $_.end; size = $_.size } })
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestOut -Encoding UTF8
L "   manifest -> $manifestOut"

if ($DryRun) { L "DryRun: skip build"; L "=== DONE (dry run) ==="; exit 0 }

if ((Test-Path $Out) -and -not $Overwrite) {
    $osz = (Get-Item $Out).Length
    if ($osz -ne $DeviceSize) {
        L "   WARN: existing output $Out is $osz bytes (not $DeviceSize); rebuilding anyway"
    } else {
        L "   existing output has expected size; will rebuild (use -SkipBuild style manual check if needed)"
    }
}

L "3) make_super.py -> $Out"
$argList = @(
    (Join-Path $tc 'make_super.py'), '-o', $Out,
    '--device-size', "$DeviceSize", '--layout', 'mtk',
    '--alignment', "$Alignment", '--first-logical-sector', "$FirstLogicalSector",
    '--group', "main_a:$GroupMainAMax"
)
if ($IncludeEmptyBSlots) { $argList += '--group'; $argList += 'main_b:9653190656' }
foreach ($o in $order) {
    $argList += '--partition'
    $argList += ("{0}:main_a:ro:{1}" -f $o[0], $o[1])
}
if ($IncludeEmptyBSlots) {
    foreach ($p in @('product_b', 'vendor_b', 'system_ext_b', 'odm_b', 'system_b', 'mi_ext_b', 'vendor_dlkm_b', 'system_dlkm_b', 'odm_dlkm_b')) {
        $argList += '--partition'
        $argList += ("{0}:main_b:ro:-" -f $p)
    }
}
$t0 = Get-Date
& $py @argList 2>&1 | ForEach-Object { L "   $_" }
$rc = $LASTEXITCODE
L ("   make_super rc=$rc, elapsed={0:N1}s" -f ((Get-Date) - $t0).TotalSeconds)
if ($rc -ne 0) { throw "make_super.py failed rc=$rc (output may be stale/partial: $Out)" }
if (-not (Test-Path $Out)) { throw "output not created: $Out" }
$osz = (Get-Item $Out).Length
if ($osz -ne $DeviceSize) { throw "output size $osz != expected $DeviceSize" }
L "   output size OK: $osz"

if (-not $SkipVerify) {
    L "4) verify_super.py (LP checksums, bounds, non-overlap, fs magic)"
    & $py (Join-Path $tc 'verify_super.py') --built $Out --expect-size $DeviceSize 2>&1 | ForEach-Object { L "   $_" }
    $vrc = $LASTEXITCODE
    L "   verify_super rc=$vrc"
    if ($vrc -ne 0) { throw "verify_super FAILED rc=$vrc" }
    $leadLp = Join-Path $proj 'scripts\lpdump.py'
    if (Test-Path $leadLp) {
        L "5) cross-check with Lead's lpdump.py"
        & $py $leadLp $Out 2>&1 | Select-Object -Last 14 | ForEach-Object { L "   $_" }
    }
}

L "6) sha256"
$h = (Get-FileHash -Algorithm SHA256 $Out).Hash.ToLower()
L ("   {0}  {1:N0} bytes ({2:N2} GiB)  sha256={3}" -f $Out, (Get-Item $Out).Length, ((Get-Item $Out).Length / 1GB), $h)
L "=== DONE (log: $log) ==="
