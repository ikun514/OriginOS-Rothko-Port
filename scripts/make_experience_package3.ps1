$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$pt = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools'
$exp = Join-Path $root '05_flash\experience'
$base = Join-Path $root '02_base\images'
$out = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience'
$zip = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience.zip'
$ascii = New-Object System.Text.ASCIIEncoding

$images = [ordered]@{
  'super_v28.img'            = 'G:\OriginOS_Work\04_build\v28_super.img'
  'vendor_boot_patched.img'  = 'G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img'
  'boot_a.img'               = Join-Path $base 'rothko_current_boot_a.img'
  'init_boot_a.img'          = Join-Path $base 'rothko_current_init_boot_a.img'
  'dtbo_a.img'               = Join-Path $base 'rothko_current_dtbo_a.img'
  'vbmeta_a.img'             = Join-Path $base 'rothko_current_vbmeta_a.img'
  'vbmeta_system_a.img'      = Join-Path $base 'rothko_current_vbmeta_system_a.img'
  'vbmeta_vendor_a.img'      = Join-Path $base 'rothko_current_vbmeta_vendor_a.img'
}

Write-Output "== prepare dir =="
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $out 'tools') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $out 'images') | Out-Null

Write-Output "== tools / scripts / readme =="
foreach ($f in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','fastboot.exe')) {
  Copy-Item (Join-Path $pt $f) (Join-Path $out "tools\$f") -Force
}
Copy-Item (Join-Path $exp 'flash_all.bat') (Join-Path $out 'flash_all.bat') -Force
Copy-Item (Join-Path $exp 'README-experience.txt') (Join-Path $out 'README-experience.txt') -Force

Write-Output "== images =="
foreach ($name in $images.Keys) {
  $src = $images[$name]
  if (-not (Test-Path $src)) { throw "missing source: $src" }
  Write-Output ("copy {0} ({1} MB)" -f $name, [math]::Round((Get-Item $src).Length/1MB))
  Copy-Item $src (Join-Path $out "images\$name") -Force
}

Write-Output "== checksums =="
$lines = @()
foreach ($name in $images.Keys) { $lines += ("{0}  images\{1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $out "images\$name")).Hash, $name) }
foreach ($f in @('tools\adb.exe','tools\fastboot.exe','flash_all.bat')) {
  $lines += ("{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $out $f)).Hash, $f)
}
[System.IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS.txt'), (($lines -join "`r`n") + "`r`n"), $ascii)

Write-Output "== zip (store mode) =="
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$level = [System.IO.Compression.CompressionLevel]::NoCompression
[System.IO.Compression.ZipFile]::CreateFromDirectory($out, $zip, $level, $false)
Write-Output ("ZIP_GB=" + [math]::Round((Get-Item $zip).Length / 1GB, 2))
Write-Output ("DIR_GB=" + [math]::Round(((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1GB), 2))
Get-ChildItem $out -Recurse -File | Select-Object FullName, @{n='MB';e={[math]::Round($_.Length/1MB)}} | Format-Table -AutoSize
Write-Output "PACKAGE_DONE"
