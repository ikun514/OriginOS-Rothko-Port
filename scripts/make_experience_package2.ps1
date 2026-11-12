$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$pt = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools'
$src = Join-Path $root '05_flash\experience'
$out = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience'
$zip = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience.zip'
$super = 'G:\OriginOS_Work\04_build\v28_super.img'
$vb = 'G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img'
$ascii = New-Object System.Text.ASCIIEncoding

Write-Output "== prepare dir =="
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $out 'tools') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $out 'images') | Out-Null

Write-Output "== copy tools + scripts + readme =="
foreach ($f in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','fastboot.exe')) {
  Copy-Item (Join-Path $pt $f) (Join-Path $out "tools\$f") -Force
}
Copy-Item (Join-Path $src 'flash_all.bat') (Join-Path $out 'flash_all.bat') -Force
Copy-Item (Join-Path $src 'README-experience.txt') (Join-Path $out 'README-experience.txt') -Force

Write-Output "== copy images (large) =="
Copy-Item $super (Join-Path $out 'images\super_v28.img') -Force
Copy-Item $vb (Join-Path $out 'images\vendor_boot_patched.img') -Force

Write-Output "== checksums =="
$lines = @()
foreach ($rel in @('images\super_v28.img','images\vendor_boot_patched.img','tools\adb.exe','tools\fastboot.exe','flash_all.bat')) {
  $p = Join-Path $out $rel
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
  $lines += ("{0}  {1}" -f $h, $rel)
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
