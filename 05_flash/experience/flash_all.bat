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
echo See README-experience.txt for details.
pause
exit /b 0
:fail
echo.
echo FAILED - check fastboot driver, bootloader unlock and cable.
pause
exit /b 1
