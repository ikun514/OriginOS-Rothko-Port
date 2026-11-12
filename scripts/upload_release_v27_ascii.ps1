param([string]$Token, [string]$SuperImage = 'G:\OriginOS_Work\04_build\v27_super.img', [string]$Tag = 'v27')
$ErrorActionPreference = 'Stop'
$work = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\00_tools\release_v27'
$headers = @{ Authorization = "token $Token"; 'User-Agent' = 'dsh-port'; Accept = 'application/vnd.github+json' }
$api = 'https://api.github.com/repos/ikun514/OriginOS-Rothko-Port'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$rel = $null
try { $rel = Invoke-RestMethod -Uri "$api/releases/tags/$Tag" -Headers $headers -TimeoutSec 30 } catch { }
if (-not $rel) {
  $body = @{ tag_name = $Tag; target_commitish = 'main'; name = 'v27 super (OriginOS 6 on Redmi K70 Ultra)'; body = 'OriginOS 6 ported to Redmi K70 Ultra (rothko). v27 super image split into <2GB parts.'; draft = $false; prerelease = $false } | ConvertTo-Json
  $rel = Invoke-RestMethod -Uri "$api/releases" -Method Post -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 60
}
Write-Output "release id=$($rel.id)"
$uploadUrl = $rel.upload_url -replace '\{.*\}$', ''
$chunk = 1900000000
$parts = @()
$existingParts = Get-ChildItem $work -Filter 'v27_super.img.part*' -ErrorAction SilentlyContinue | Sort-Object Name
if ($existingParts.Count -gt 0) { $parts = $existingParts | ForEach-Object { $_.FullName } }
else {
  $fs = [System.IO.File]::OpenRead($SuperImage); $i = 0
  while ($true) {
    $buf = New-Object byte[] $chunk
    $read = $fs.Read($buf, 0, $chunk)
    if ($read -le 0) { break }
    $out = Join-Path $work ("v27_super.img.part{0:D2}" -f $i)
    $ofs = [System.IO.File]::Create($out); $ofs.Write($buf, 0, $read); $ofs.Close()
    $parts += $out; $i++
    if ($read -lt $chunk) { break }
  }
  $fs.Close()
}
$sumBytes = 0; foreach ($p in $parts) { $sumBytes += (Get-Item $p).Length }
Write-Output ("parts={0} totalBytes={1}" -f $parts.Count, $sumBytes)
$sums = @(); $sums += ("{0}  v27_super.img" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $SuperImage).Hash)
foreach ($p in $parts) { $sums += ("{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash, (Split-Path $p -Leaf)) }
$sumFile = Join-Path $work 'SHA256SUMS.txt'; Set-Content -Path $sumFile -Value ($sums -join "`r`n") -Encoding ascii
$readme = Join-Path $work 'INSTALL.txt'
$lines = @('OriginOS 6 (PD2339) -> Redmi K70 Ultra (rothko) - v27 super package','','Join parts (Linux/macOS): cat v27_super.img.part* > v27_super.img','Join parts (PowerShell):',' $out=[System.IO.File]::Create("v27_super.img"); Get-ChildItem v27_super.img.part* | Sort-Object Name | ForEach-Object { $b=[System.IO.File]::ReadAllBytes($_.FullName); $out.Write($b,0,$b.Length) }; $out.Close()','','Verify: sha256sum -c SHA256SUMS.txt','','Flash: fastboot flash super v27_super.img && fastboot -w && fastboot reboot','','Contains super partition only. Requires matching HyperOS base and patched vendor_boot/init_boot.')
Set-Content -Path $readme -Value ($lines -join "`r`n") -Encoding ascii
$existing = @(); try { $existing = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 30 } catch { }
$assets = @($sumFile, $readme) + $parts
foreach ($a in $assets) {
  $name = Split-Path $a -Leaf
  if ($existing | Where-Object { $_.name -eq $name -and $_.state -eq 'uploaded' }) { Write-Output "skip $name"; continue }
  $ok = $false
  for ($try = 1; $try -le 4 -and -not $ok; $try++) {
    Write-Output ("upload {0} try{1} size={2}" -f $name, $try, (Get-Item $a).Length)
    & curl.exe -sS -X POST -H "Authorization: token $Token" -H "Content-Type: application/octet-stream" --data-binary "@$a" --max-time 10800 --retry 1 "$uploadUrl?name=$name" -o (Join-Path $work ("resp_$name.json")) -w "http=%{http_code} t=%{time_total}s`n"
    Start-Sleep -Seconds 3
    try {
      $now = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 60
      if ($now | Where-Object { $_.name -eq $name -and $_.state -eq 'uploaded' }) { $ok = $true; Write-Output "ok $name" }
    } catch { }
    if (-not $ok) { Start-Sleep -Seconds 15 }
  }
  if (-not $ok) { Write-Output "FAILED $name" }
}
$final = Invoke-RestMethod -Uri "$api/releases/$($rel.id)/assets?per_page=100" -Headers $headers -TimeoutSec 60
$final | Select-Object name, size, state | Format-Table -AutoSize
Write-Output ("URL: " + $rel.html_url)
