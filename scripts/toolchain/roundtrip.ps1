param(
    [string]$WorkDir = '',
    [switch]$KeepRemote
)
# roundtrip.ps1 -- PC 端编排 "目录 -> tar -> push -> 手机打包 erofs -> loop 挂载 -> sha256 校验 -> 取回镜像"
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File roundtrip.ps1
$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy -Scope Process Bypass -Force

$adb = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools\adb.exe'
$proj = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$tc = Join-Path $proj 'scripts\toolchain'
if (-not $WorkDir) { $WorkDir = Join-Path $proj '04_build\lab\erofs_roundtrip' }
$log = Join-Path $proj '06_logs\toolchain_erofs_roundtrip.log'

function L([string]$m) {
    $t = Get-Date -Format 'HH:mm:ss'
    $line = "$t $m"
    Write-Host $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}

Set-Content -Path $log -Value "=== erofs roundtrip $(Get-Date -Format o) ===" -Encoding UTF8

# 1. 本地构造目录树
$tree = Join-Path $WorkDir 'tree'
if (Test-Path $tree) { Remove-Item $tree -Recurse -Force }
New-Item -ItemType Directory -Path $tree -Force | Out-Null
L "1) build local tree: $tree"
$dirs = @('bin', 'etc', 'etc/init', 'lib64', 'app/SystemApp', 'priv-app/PrivApp', 'overlay/framework', 'usr/share/doc')
foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $tree $d) -Force | Out-Null }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
for ($i = 0; $i -lt 12; $i++) {
    $content = "file $i`n" + ("A" * (200 + $i * 37)) + "`n" + ("random-line-$i " * (10 + $i))
    [IO.File]::WriteAllText((Join-Path $tree ("etc/file_{0:d2}.conf" -f $i)), $content, $utf8NoBom)
}
$exe = "#!/system/bin/sh`necho hello-from-package`nexit 0`n"
[IO.File]::WriteAllText((Join-Path $tree 'bin/test_service.sh'), $exe, $utf8NoBom)
$rnd = New-Object byte[] 262144
(New-Object Random(42)).NextBytes($rnd)
[IO.File]::WriteAllBytes((Join-Path $tree 'app/SystemApp/SystemApp.apk'), $rnd)
$rnd2 = New-Object byte[] 131072
(New-Object Random(7)).NextBytes($rnd2)
[IO.File]::WriteAllBytes((Join-Path $tree 'priv-app/PrivApp/PrivApp.apk'), $rnd2)
[IO.File]::WriteAllText((Join-Path $tree 'usr/share/doc/read me first.txt'), "space in name`n", $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $tree 'usr/share/doc/中文说明.txt'), "unicode name`n", $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $tree 'etc/init/init.test.rc'), "service test /system/bin/sh`n    disabled`n", $utf8NoBom)
try {
    New-Item -ItemType SymbolicLink -Path (Join-Path $tree 'bin/sh') -Target '/system/bin/sh' -ErrorAction Stop | Out-Null
    L "   symlink created: bin/sh -> /system/bin/sh"
} catch {
    L "   WARN: cannot create symlink on Windows ($($_.Exception.Message)); 设备端已有符号链接验证"
}
[IO.File]::WriteAllBytes((Join-Path $tree 'etc/empty_file'), @())

$localFiles = Get-ChildItem $tree -Recurse -File
L ("   local tree: {0} files, {1:N0} bytes" -f $localFiles.Count, ($localFiles | Measure-Object Length -Sum).Sum)
$localHashes = $localFiles | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.FullName.Substring($tree.Length + 1).Replace('\', '/') } | Sort-Object
Add-Content -Path $log -Value "--- local sha256 ---" -Encoding UTF8
$localHashes | ForEach-Object { Add-Content -Path $log -Value $_ -Encoding UTF8 }

# 2. tar.gz
$tgz = Join-Path $WorkDir 'tree.tar.gz'
if (Test-Path $tgz) { Remove-Item $tgz -Force }
L "2) create tar.gz"
& tar.exe -czf $tgz -C $tree . 2>&1 | ForEach-Object { L "   tar: $_" }
if (-not (Test-Path $tgz)) { throw "tar.exe failed" }
L ("   archive: {0} ({1:N0} bytes)" -f $tgz, (Get-Item $tgz).Length)

# 3. push
L "3) push scripts + archive"
& $adb shell "mkdir -p /data/local/tmp/toolchain" | Out-Null
foreach ($f in @('dev_lib.sh', 'pack_erofs.sh', 'pack_ext4.sh', 'roundtrip_erofs.sh')) {
    & $adb push (Join-Path $tc $f) "/data/local/tmp/toolchain/$f" 2>&1 | ForEach-Object { L "   push: $_" }
    & $adb shell "sed -i 's/\r$//' /data/local/tmp/toolchain/$f; chmod 755 /data/local/tmp/toolchain/$f" | Out-Null
}
& $adb push $tgz "/data/local/tmp/$(Split-Path $tgz -Leaf)" 2>&1 | ForEach-Object { L "   push: $_" }

# 4. run on device
$tgzName = Split-Path $tgz -Leaf
$cmd = "sh /data/local/tmp/toolchain/roundtrip_erofs.sh /data/local/tmp/$tgzName /data/local/tmp/lab/roundtrip /data/local/tmp/lab/roundtrip/tree.erofs"
L "4) run on device: $cmd"
$t0 = Get-Date
$out = & $adb shell su -c $cmd 2>&1
$out | ForEach-Object { L $_ }
L ("   device run finished in {0:N1}s" -f ((Get-Date) - $t0).TotalSeconds)

# 5. pull image + report
L "5) pull image + report"
$pullDir = Join-Path $proj '04_build\lab\from_device'
New-Item -ItemType Directory -Path $pullDir -Force | Out-Null
& $adb pull /data/local/tmp/lab/roundtrip/tree.erofs (Join-Path $pullDir 'tree.erofs') 2>&1 | ForEach-Object { L "   pull: $_" }
& $adb pull /data/local/tmp/lab/roundtrip/roundtrip_report.txt (Join-Path $pullDir 'roundtrip_report.txt') 2>&1 | ForEach-Object { L "   pull: $_" }
& $adb pull /data/local/tmp/lab/roundtrip/mnt.sha256 (Join-Path $pullDir 'mnt.sha256') 2>&1 | ForEach-Object { L "   pull: $_" }

if (-not $KeepRemote) {
    & $adb shell su -c "rm -rf /data/local/tmp/lab/roundtrip/src" 2>&1 | Out-Null
}

# 6. 校验
L "6) verify"
$img = Join-Path $pullDir 'tree.erofs'
if (Test-Path $img) {
    $h = (Get-FileHash $img -Algorithm SHA256).Hash.ToLower()
    $head = [IO.File]::ReadAllBytes($img)
    $magic = [BitConverter]::ToString($head[1024..1027]).Replace('-', '').ToLower()
    L ("   image {0}: {1:N0} bytes sha256={2} erofs_magic@1024={3}" -f $img, (Get-Item $img).Length, $h, $magic)
    L ("   erofs magic ok: {0}" -f ($magic -eq 'e2e1f5e0'))
}
$rep = Join-Path $pullDir 'roundtrip_report.txt'
if (Test-Path $rep) {
    $rc = Get-Content $rep
    ($rc | Where-Object { $_ -match '^checksums_match:|^image_size:|^src_entries:' }) | ForEach-Object { L "   $_" }
    $devHashes = $rc | Where-Object { $_ -match '^[0-9a-f]{64}  ' }
    $localSet = $localHashes | ForEach-Object { ($_ -split '  ')[0] } | Sort-Object
    $devSet = $devHashes | ForEach-Object { ($_ -split '  ')[0] } | Sort-Object
    $onlyLocal = $localSet | Where-Object { $devSet -notcontains $_ }
    L ("   local files: {0}, device-report files: {1}, only-local: {2}" -f $localSet.Count, $devSet.Count, @($onlyLocal).Count)
}

L "=== DONE (log: $log) ==="
