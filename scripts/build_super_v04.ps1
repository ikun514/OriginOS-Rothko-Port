param(
  [string]$Out = 'G:\OriginOS_Work\04_build\v04_super.img'
)
$ErrorActionPreference='Stop'
$root='C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$py='C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$tmp="$root\04_build_tmp"
$base="$root\02_base\images"
$vivo='G:\OriginOS_Work\03_port\images'
$parts = @(
  @{n='product_a';      f="$tmp\vivo_product_v03.img"},
  @{n='vendor_a';       f="$base\rothko_current_vendor_a.img"},
  @{n='system_ext_a';   f="$vivo\system_ext.img"},
  @{n='odm_a';          f="$tmp\rothko_odm_v03.img"},
  @{n='system_a';       f="$tmp\vivo_system_v05.img"},
  @{n='mi_ext_a';       f="$base\rothko_current_mi_ext_a.img"},
  @{n='vendor_dlkm_a';  f="$base\rothko_current_vendor_dlkm_a.img"},
  @{n='system_dlkm_a';  f="$base\rothko_current_system_dlkm_a.img"},
  @{n='odm_dlkm_a';     f="$base\rothko_current_odm_dlkm_a.img"}
)
$sum=0
Write-Output "== layout =="
foreach($p in $parts){
  if(-not (Test-Path $p.f)){ throw "missing image: $($p.f)" }
  $sz=(Get-Item $p.f).Length
  $sum+=$sz
  Write-Output ("{0,-15} {1,14}  {2}" -f $p.n,$sz,$p.f)
}
$limit=9652142080
$pad=1048576*9
Write-Output ("sum = {0}; data+align = {1}; limit = {2}; margin = {3}" -f $sum,($sum+$pad),$limit,($limit-$sum-$pad))
if(($sum+$pad) -gt $limit){ throw "OVER BUDGET by $($sum+$pad-$limit) bytes" }

$argsList=@("$root\scripts\toolchain\make_super.py",'-o',$Out,'--device-size','9663676416','--layout','mtk',
  '--group','main_a:9653190656','--group','main_b:9653190656')
foreach($p in $parts){ $argsList += @('--partition',"$($p.n):main_a:ro:$($p.f)") }
& $py @argsList
if($LASTEXITCODE -ne 0){ throw "make_super failed: $LASTEXITCODE" }
Write-Output "== verify =="
& $py "$root\scripts\lpdump.py" $Out 2>&1 | Select-Object -Last 16
Write-Output ("size=" + (Get-Item $Out).Length)
Write-Output ("sha256=" + (Get-FileHash -Algorithm SHA256 $Out).Hash)
