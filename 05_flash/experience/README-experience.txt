OriginOS 6 (vivo PD2339) port - experience package v28
=====================================================

Target device : Redmi K70 Ultra (rothko, 2407FRK8EC, MT6989)
Port source   : vivo PD2339 (iQOO Neo9 Pro / Neo9S Pro) OriginOS 6 / Android 16 / 16.2.13.1.W10
Project       : https://github.com/ikun514/OriginOS-Rothko-Port

== Contents ==
  flash_all.bat                    one-click flash script (Windows)
  tools\adb.exe, fastboot.exe ...  adb / fastboot binaries
  images\super_v28.img             super partition image (system/vendor/product/odm/... all logical partitions)
  images\vendor_boot_patched.img   patched vendor_boot (AVB tokens removed, required for booting)
  SHA256SUMS.txt                   checksums

== Requirements ==
  1. Redmi K70 Ultra with unlocked bootloader
  2. Stock HyperOS 3.0.303 base firmware (all non-super partitions stay stock)
  3. Windows with fastboot driver installed (device shows Android Bootloader Interface)

== Flash steps ==
  1. Power off; hold Volume-Down + Power to enter bootloader (FASTBOOT screen)
  2. Connect USB cable
  3. Run flash_all.bat and follow prompts (flashes vendor_boot + super, optional /data wipe)
  4. First boot takes 1-3 minutes; the script then enables USB debugging and mounts external storage

== Working features (tested on v28) ==
  boot to launcher, touch, display, Wi-Fi, Bluetooth on/off, 5G mobile network (China Mobile NR_SA),
  audio, 50 hardware sensors, USB debugging (adb over USB), OOBE skipped,
  About phone shows "Redmi K70 Ultra", vivo account can log in

== Known limitations (v28) ==
  - Camera: not available (vivo private camera stack; media.camera service not registered)
  - Vibration: not available (only Xiaomi vibratorfeature HAL; no AOSP default vibrator instance)
  - MTP file transfer: not available (adb-only USB composition chosen so USB debugging works)
  - Status bar height: too short (needs a vivo SystemUI resource overlay)
  - Gallery / MediaStore: vold aborts once at boot (missing libblkid.so) so external storage is not
    mounted automatically; flash_all.bat runs: adb shell sm mount "emulated;0" as a workaround
    (after every reboot you may need to run it again)
  - Bluetooth scanning may fail

== Rollback ==
  fastboot flash super <stock_super.img>
  fastboot -w
  fastboot reboot

== Disclaimer ==
  For personal research only. Flashing carries risk (brick / data loss / warranty void).
  Firmware copyright belongs to vivo / Xiaomi. This package contains only partition images built
  from firmware the user owns; it does not redistribute vendor firmware archives.
