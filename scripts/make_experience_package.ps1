$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port'
$pt = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\tools\platform-tools'
$out = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience'
$zip = 'G:\OriginOS_Work\release\OriginOS6_rothko_v28_experience.zip'
$super = 'G:\OriginOS_Work\04_build\v28_super.img'
$vb = 'G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img'

Write-Output "== prepare dir =="
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $out 'tools') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $out 'images') | Out-Null

Write-Output "== copy tools =="
foreach ($f in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','fastboot.exe')) {
  Copy-Item (Join-Path $pt $f) (Join-Path $out "tools\$f") -Force
}

Write-Output "== copy images (this takes a while) =="
Copy-Item $super (Join-Path $out 'images\super_v28.img') -Force
Copy-Item $vb (Join-Path $out 'images\vendor_boot_patched.img') -Force

$bat = @'
@echo off
setlocal
cd /d "%~dp0"
set "ADB=%~dp0tools\adb.exe"
set "FB=%~dp0tools\fastboot.exe"
echo ============================================================
echo  OriginOS 6 (vivo PD2339) port for Redmi K70 Ultra (rothko)
echo  Experience package v28 - USE AT YOUR OWN RISK
echo ============================================================
echo.
echo Requirements:
echo   - bootloader unlocked
echo   - matching HyperOS 3.0.303 base firmware already on the phone
echo   - phone is NOW in bootloader fastboot mode (Vol- + Power), USB connected
echo.
pause
echo [1/4] checking fastboot device...
"%FB%" devices
if errorlevel 1 goto fail
echo [2/4] flashing patched vendor_boot (AVB tokens removed)...
"%FB%" flash vendor_boot "images\vendor_boot_patched.img"
if errorlevel 1 goto fail
echo [3/4] flashing super v28 (takes 4-6 minutes, do not unplug)...
"%FB%" flash super "images\super_v28.img"
if errorlevel 1 goto fail
set /p WIPE=Wipe /data now? recommended for first install [y/N]:
if /i "%WIPE%"=="y" "%FB%" -w
echo [4/4] rebooting...
"%FB%" reboot
echo.
echo waiting for adb (up to 6 min)...
"%ADB%" wait-for-device
timeout /t 120 /nobreak
echo.
echo applying post-boot fixes (usb debugging + external storage mount)...
"%ADB%" shell settings put global development_settings_enabled 1
"%ADB%" shell settings put global adb_enabled 1
"%ADB%" shell sm mount "emulated;0"
echo.
echo DONE. Known limitations: camera, vibration, MTP, status bar height, Bluetooth scan.
echo See README-体验版.txt for details.
pause
exit /b 0
:fail
echo.
echo FAILED - check fastboot driver, bootloader unlock and cable.
pause
exit /b 1
'@
$batPath = Join-Path $out 'flash_all.bat'
Set-Content -Path $batPath -Value ($bat -replace "`n","`r`n") -Encoding ascii

$readme = @'
OriginOS 6 (vivo PD2339) 移植体验包 v28
=======================================
目标机型: Redmi K70 Ultra (rothko, 2407FRK8EC, MT6989)
移植来源: vivo PD2339 (iQOO Neo9 Pro / Neo9S Pro) OriginOS 6 / Android 16 / 16.2.13.1.W10
项目主页: https://github.com/ikun514/OriginOS-Rothko-Port

一、包内容
  flash_all.bat                 一键刷机脚本 (Windows)
  tools\adb.exe 等              adb/fastboot 工具
  images\super_v28.img          super 镜像 (system/vendor/product/odm/... 全部逻辑分区)
  images\vendor_boot_patched.img 修改过的 vendor_boot (去掉 AVB 校验, 必需的引导补丁)
  SHA256SUMS.txt                校验值

二、前置条件 (缺一不可)
  1. Redmi K70 Ultra 已解 BL 锁
  2. 手机上仍是 HyperOS 3.0.303 同代原厂固件 (super 之外的分区保持原厂)
  3. Windows 已安装 fastboot 驱动 (设备在 fastboot 模式应显示 Android Bootloader Interface)

三、刷机步骤
  1. 手机关机, 按住 音量下 + 电源 进入 bootloader (屏幕显示 FASTBOOT)
  2. 数据线连接电脑
  3. 双击 flash_all.bat, 按提示操作 (会刷 vendor_boot + super, 可选清 /data)
  4. 首次开机需 1-3 分钟, 之后脚本会自动开 USB 调试并尝试挂载外部存储

四、已实现功能 (实测)
  正常开机 / 桌面 / 触控 / 显示 / Wi-Fi / 蓝牙开关 / 移动网络 5G / 音频 / 传感器 / USB 调试
  OOBE 已跳过; 关于本机型号显示 Redmi K70 Ultra; vivo 账号可登录

五、已知限制 (v28)
  - 相机不可用 (vivo 私有相机栈, media.camera 未注册)
  - 震动不可用 (只有小米 vibratorfeature HAL, AOSP vibrator_manager 找不到 default 实例)
  - MTP 文件传输不可用 (当前为保证 USB 调试采用 adb-only 组合)
  - 状态栏高度偏矮 (需要 vivo SystemUI 的资源 overlay 才能改)
  - 相册/媒体库: vold 启动会崩一次 (缺 libblkid.so) 导致外部存储未挂载;
    脚本已自动执行 adb shell sm mount "emulated;0" 临时挂载, 重启后可能需要重新执行
  - 蓝牙扫描可能失败

六、回滚
  刷回原厂 super (需自备本机型原厂固件) 即可:
    fastboot flash super <原厂 super.img>
    fastboot -w
    fastboot reboot

七、免责声明
  本包仅供个人学习研究, 刷机有风险 (变砖/丢数据/保修失效), 操作前请自行备份.
  固件版权归 vivo / 小米所有, 本包不含任何厂商固件之外的额外商业内容.
'@
$readmePath = Join-Path $out 'README-体验版.txt'
Set-Content -Path $readmePath -Value ($readme -replace "`n","`r`n") -Encoding utf8

Write-Output "== checksums =="
$lines = @()
foreach ($rel in @('images\super_v28.img','images\vendor_boot_patched.img','tools\adb.exe','tools\fastboot.exe','flash_all.bat')) {
  $p = Join-Path $out $rel
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
  $lines += ("{0}  {1}" -f $h, $rel)
}
Set-Content -Path (Join-Path $out 'SHA256SUMS.txt') -Value ($lines -join "`r`n") -Encoding ascii

Write-Output "== zip (store mode, zip64) =="
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$level = [System.IO.Compression.CompressionLevel]::NoCompression
[System.IO.Compression.ZipFile]::CreateFromDirectory($out, $zip, $level, $false)
Write-Output ("zip size = {0} GB" -f [math]::Round((Get-Item $zip).Length / 1GB, 2))
Write-Output ("dir size = {0} GB" -f [math]::Round(((Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum / 1GB), 2))
Get-ChildItem $out -Recurse -File | Select-Object FullName, @{n='MB';e={[math]::Round($_.Length/1MB)}} | Format-Table -AutoSize
Write-Output "PACKAGE_DONE"
