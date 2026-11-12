u{FEFF}param(
  [string]$Token,
  [string]$SuperImage = 'G:\OriginOS_Work\04_build\v27_super.img',
  [string]$Tag = 'v27',
  [string]$Title = 'v27 super (OriginOS 6 on Redmi K70 Ultra)'
)
$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$work = Join-Path $root '00_tools\release_v27'
$headers = @{ Authorization = "token $Token"; 'User-Agent' = 'dsh-port'; Accept = 'application/vnd.github+json' }
$owner = 'ikun514'; $repo = 'OriginOS-Rothko-Port'
$api = "https://api.github.com/repos/$owner/$repo"
New-Item -ItemType Directory -Force -Path $work | Out-Null

Write-Output "== ensure release $Tag =="
$rel = $null
try { $rel = Invoke-RestMethod -Uri "$api/releases/tags/$Tag" -Headers $headers -TimeoutSec 30 } catch { }
if (-not $rel) {
  $body = @{ tag_name = $Tag; target_commitish = 'main'; name = $Title; body = 'OriginOS 6 (PD2339) ported to Redmi K70 Ultra (rothko) - v27 super image, split into <2GB parts. See repo README / 07_docs/STATUS_2026-08-12_HANDOVER.md for details.'; draft = $false; prerelease = $false } | ConvertTo-Json
  $rel = Invoke-RestMethod -Uri "$api/releases" -Method Post -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 60
  Write-Output "created release id=$($rel.id)"
} else { Write-Output "release exists id=$($rel.id)" }
$uploadUrl = $rel.upload_url -replace '\{.*\}$', ''

Write-Output "== split super into parts =="
$chunk = 1900000000
$parts = @()
$existingParts = Get-ChildItem $work -Filter 'v27_super.img.part*' -ErrorAction SilentlyContinue | Sort-Object Name
if ($existingParts.Count -gt 0) {
  $parts = $existingParts | ForEach-Object { $_.FullName }
} else {
  $fs = [System.IO.File]::OpenRead($SuperImage)
  $i = 0
  while ($true) {
    $buf = New-Object byte[] $chunk
    $read = $fs.Read($buf, 0, $chunk)
    if ($read -le 0) { break }
    $out = Join-Path $work ("v27_super.img.part{0:D2}" -f $i)
    $ofs = [System.IO.File]::Create($out)
    $ofs.Write($buf, 0, $read); $ofs.Close()
    $parts += $out
    $i++
    if ($read -lt $chunk) { break }
  }
  $fs.Close()
}
$sumBytes = 0; foreach ($p in $parts) { $sumBytes += (Get-Item $p).Length }
Write-Output ("parts={0} totalBytes={1}" -f $parts.Count, $sumBytes)

Write-Output "== checksums =="
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $SuperImage).Hash
$sums = @()
$sums += ("{0}  v27_super.img" -f $sha)
foreach ($p in $parts) { $sums += ("{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash, (Split-Path $p -Leaf)) }
$sumFile = Join-Path $work 'SHA256SUMS.txt'
Set-Content -Path $sumFile -Value ($sums -join "`r`n") -Encoding ascii

$readme = Join-Path $work 'INSTALL.txt'
$lines = @(
  'OriginOS 6 (PD2339) -> Redmi K70 Ultra (rothko) - v27 super flashable package',
  '',
  'Join parts (PowerShell):',
  '  $out = [System.IO.File]::Create("v27_super.img")',
  '  Get-ChildItem v27_super.img.part* | Sort-Object Name | ForEach-Object { $b=[System.IO.File]::ReadAllBytes($_.FullName); $out.Write($b,0,$b.Length) }',
  '  $out.Close()',
  '',
  'Join parts (Linux/macOS):',
  '  cat v27_super.img.part* > v27_super.img',
  '',
  'Verify:',
  '  sha256sum -c SHA256SUMS.txt',
  '',
  'Flash (device in bootloader fastboot, unlocked, windows fastboot driver installed):',
  '  fastboot flash super v27_super.img',
  '  fastboot -w',
  '  fastboot reboot',
  '',
  'Notes:',
  '- This package contains only the super partition (system/vendor/product/odm logical partitions).',
  '- Requires matching HyperOS 3.0.303 base firmware and patched vendor_boot/init_boot per repo docs.',
  '- Flash at your own risk.'
)
Set-Content -Path $readme -Value ($lines -join "`r`n") -Encoding ascii

Write-Output "== upload assets =="
$assets = @($sumFile, $readme) + $parts
$existing = @()
try { $existing = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 30 } catch { }
foreach ($a in $assets) {
  $name = Split-Path $a -Leaf
  $hit = $existing | Where-Object { $_.name -eq $name -and $_.state -eq 'uploaded' }
  if ($hit) { Write-Output "skip exists: $name"; continue }
  if ($existing | Where-Object { $_.name -eq $name -and $_.state -ne 'uploaded' }) {
    $del = $existing | Where-Object { $_.name -eq $name -and $_.state -ne 'uploaded' }
    foreach ($d in $del) { try { Invoke-RestMethod -Uri "$api/releases/assets/$($d.id)" -Method Delete -Headers $headers -TimeoutSec 30 } catch { } }
  }
  $ok = $false
  for ($try = 1; $try -le 4 -and -not $ok; $try++) {
    Write-Output ("uploading {0} (try {1}) size={2}" -f $name, $try, (Get-Item $a).Length)
    & curl.exe -sS -X POST -H "Authorization: token $Token" -H "Content-Type: application/octet-stream" --data-binary "@$a" --max-time 10800 --retry 1 --retry-delay 10 "$uploadUrl?name=$name" -o (Join-Path $work ("resp_$name.json")) -w "http=%{http_code} time=%{time_total}s`n"
    Start-Sleep -Seconds 3
    try {
      $assetsNow = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 60
      $chk = $assetsNow | Where-Object { $_.name -eq $name -and $_.state -eq 'uploaded' }
      if ($chk) { $ok = $true; Write-Output ("ok {0} size={1}" -f $name, $chk.size) }
    } catch { }
    if (-not $ok) { Start-Sleep -Seconds 10 }
  }
  if (-not $ok) { Write-Output ("FAILED {0}" -f $name) }
}
Write-Output "== final assets =="
$final = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 60
$final | Select-Object name, size, state | Format-Table -AutoSize
Write-Output ("URL: {0}" -f $rel.html_url)
