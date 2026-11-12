param(
    [string]$Product = '',
    [string]$Vendor = '',
    [string]$SystemExt = '',
    [string]$Odm = '',
    [string]$System = '',
    [string]$MiExt = '',
    [string]$VendorDlkm = '',
    [string]$SystemDlkm = '',
    [string]$OdmDlkm = '',
    [string]$Out = 'G:\OriginOS_Work\04_build\super_v02.img',
    [int64]$DeviceSize = 9663676416,
    [int64]$GroupMainAMax = 9652142080,
    [switch]$IncludeEmptyBSlots,
    [switch]$SkipVerify,
    [switch]$DryRun
)
# build_v02_super.ps1 -- build v0.2 super.img (9 partitions, order fixed) + size budget check + self verify.
# Order (Lead-defined): product, vendor, system_ext, odm, system, mi_ext, vendor_dlkm, system_dlkm, odm_dlkm
# NOTE: keep this file ASCII-only (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$proj = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$tc = Join-Path $proj 'scripts\toolchain'
$py = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$log = Join-Path $proj '06_logs\build_v02_super.log'

function L([string]$m) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $m"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}
Set-Content -Path $log -Value "=== build_v02_super $(Get-Date -Format o) ===" -Encoding UTF8

# default inputs: vivo images from G:\OriginOS_Work\03_port\images, rothko from 02_base\images
$vivoDir = 'G:\OriginOS_Work\03_port\images'
$rothkoDir = Join-Path $proj '02_base\images'
if (-not $Product) { $Product = Join-Path $vivoDir 'product.img' }
if (-not $SystemExt) { $SystemExt = Join-Path $vivoDir 'system_ext.img' }
if (-not $System) { $System = Join-Path $vivoDir 'system.img' }
if (-not $Vendor) { $Vendor = Join-Path $rothkoDir 'rothko_current_vendor_a.img' }
if (-not $Odm) { $Odm = Join-Path $rothkoDir 'rothko_current_odm_a.img' }
if (-not $MiExt) { $MiExt = Join-Path $rothkoDir 'rothko_current_mi_ext_a.img' }
if (-not $VendorDlkm) { $VendorDlkm = Join-Path $rothkoDir 'rothko_current_vendor_dlkm_a.img' }
if (-not $SystemDlkm) { $SystemDlkm = Join-Path $rothkoDir 'rothko_current_system_dlkm_a.img' }
if (-not $OdmDlkm) { $OdmDlkm = Join-Path $rothkoDir 'rothko_current_odm_dlkm_a.img' }

# ordered partition spec: name, group, image
$order = @(
    @('product_a', $Product),
    @('vendor_a', $Vendor),
    @('system_ext_a', $SystemExt),
    @('odm_a', $Odm),
    @('system_a', $System),
    @('mi_ext_a', $MiExt),
    @('vendor_dlkm_a', $VendorDlkm),
    @('system_dlkm_a', $SystemDlkm),
    @('odm_dlkm_a', $OdmDlkm)
)

L "1) input images"
$sum = [int64]0
$rows = @()
foreach ($o in $order) {
    $name = $o[0]; $path = $o[1]
    if (-not (Test-Path $path)) { throw "missing input image for $name : $path" }
    $fi = Get-Item $path
    $sum += $fi.Length
    $rows += [pscustomobject]@{ Name = $name; Size = $fi.Length; Path = $path; MiB = [math]::Round($fi.Length / 1MB, 2) }
    L ("   {0,-16} {1,14:N0} B  {2,10:N2} MiB  {3}" -f $name, $fi.Length, ($fi.Length / 1MB), $path)
}
$rows | Format-Table -AutoSize | Out-String | ForEach-Object { L "   $_" }

L "2) size budget"
$dataStart = [int64]1048576                      # first_logical_sector=2048 * 512
$availInDevice = $DeviceSize - $dataStart        # bytes usable for partition data
$slackGroup = $GroupMainAMax - $sum
$slackDevice = $availInDevice - $sum
L ("   sum of partitions      = {0:N0} B ({1:N2} GiB)" -f $sum, ($sum / 1GB))
L ("   group main_a max       = {0:N0} B ({1:N2} GiB)   slack = {2:N0} B ({3:N2} GiB)" -f $GroupMainAMax, ($GroupMainAMax / 1GB), $slackGroup, ($slackGroup / 1GB))
L ("   device data capacity   = {0:N0} B (device {1:N0} - first_logical {2:N0})   slack = {3:N0} B" -f $availInDevice, $DeviceSize, $dataStart, $slackDevice)
if ($slackGroup -lt 0) { throw "OVER BUDGET: partitions exceed group main_a max by $([math]::Abs($slackGroup)) bytes" }
if ($slackDevice -lt 0) { throw "OVER BUDGET: partitions exceed device data capacity by $([math]::Abs($slackDevice)) bytes" }
L "   budget check: PASS"

if ($DryRun) { L "DryRun: skip build"; L "=== DONE (dry run) ==="; exit 0 }

L "3) make_super.py -> $Out (layout=mtk, device-size=$DeviceSize)"
$argList = @(
    (Join-Path $tc 'make_super.py'), '-o', $Out,
    '--device-size', "$DeviceSize", '--layout', 'mtk',
    '--group', "main_a:$GroupMainAMax"
)
if ($IncludeEmptyBSlots) { $argList += '--group'; $argList += "main_b:$GroupMainAMax" }
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
& $py @argList 2>&1 | ForEach-Object { L "   $_" }
if ($LASTEXITCODE -ne 0) { throw "make_super.py failed" }

L "4) verify_super.py"
if (-not $SkipVerify) {
    & $py (Join-Path $tc 'verify_super.py') --built $Out --expect-size $DeviceSize 2>&1 | ForEach-Object { L "   $_" }
    if ($LASTEXITCODE -ne 0) { throw "verify_super FAILED" }
}

L "5) output"
$h = (Get-FileHash $Out -Algorithm SHA256).Hash.ToLower()
L ("   {0}  {1:N0} bytes ({2:N2} GiB)  sha256={3}" -f $Out, (Get-Item $Out).Length, ((Get-Item $Out).Length / 1GB), $h)
L ("   remaining headroom after build: group={0:N0} B, device={1:N0} B" -f $slackGroup, $slackDevice)
L "=== DONE (log: $log) ==="
