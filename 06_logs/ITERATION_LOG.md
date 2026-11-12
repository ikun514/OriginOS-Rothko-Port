# 刷机迭代记录（ITERATION LOG）

## v0.1 — 刷机链路验证（rothko 原内容重建 super）
- 目的：验证 lpmake 重建的 super + OrangeFox recovery adb + dd 刷写 + 启动链路
- 构建：`G:\OriginOS_Work\02_base\super_v01_rothko_rebuild.img`（toolsmith 构建，9,663,676,416B，前 208,896B 元数据与原始 super sha256 完全相同 bc7a52ed…，9/9 分区数据 sha256 MATCH）
- 刷写（2026-11-12 01:34，OrangeFox recovery，adb root）：
  - `dd if=/sdcard/work/flash/v01_rothko_super.img of=/dev/block/by-name/super bs=4M conv=fsync`
  - 9,663,676,416B / 11.657s（791MB/s）；尾部 1MiB 回读 sha256 一致
- 结果：**PASS**。重启后 `sys.boot_completed=1`，
  fingerprint=`Redmi/rothko/rothko:16/BP2A.250605.031.A3/OS3.0.303.0.WNNCNXM:user/release-keys`，slot=_a。
- 结论：super 重建（mtk 布局、单 extent、10.2 元数据）与 recovery dd 刷写链路可用；后续所有刷机沿用此通道（不使用 fastbootd，橙狐 fastbootd 已损坏）。

## v0.2 — vivo OriginOS 16 系统首启（准备中）
### 移植源
- vivo PD2339（iQOO Neo9 Pro，mt6989）OriginOS 16 / Android 16，`PD2339_A_16.2.13.1.W10.V000L1`，全量包已解出 38 个分区镜像（payload_extract.py，sha256 全部与 payload 清单 MATCH）。
- vivo system 精简打包（手机端 mkfs.erofs 1.8.3, lz4hc level=9, --file-contexts=vivo plat_file_contexts, -T 0）：
  - 全量重打包 7,782,260,736B（原 7,934,083,072B；inodes 19182 一致 → 树结构正确）
  - 两轮精简（删 /system/custom 非核心预装 + VivoGptAgent/VivoUnionApk/Baidu/AIService）→ **5,894,299,648B**（`vivo_system_v03.img`，sha256 cb4878d4…）
  - 保留：framework/vivo-res.apk、SystemUI(Plugin)、Settings、JoviIme、VivoCamera、VivoGallery、主题资源、apex、libs、etc 全部
### super 布局（v02）
| 分区 | 来源 | 大小 |
|---|---|---|
| system_a | vivo 精简 | 5,894,299,648 |
| system_ext_a | vivo 原镜像 | 411,910,144 |
| product_a | vivo 原镜像 | 393,981,952 |
| vendor_a | rothko 原厂 | 1,644,707,840 |
| odm_a | rothko 原厂 | 881,057,792 |
| mi_ext_a | rothko 原厂 | 126,640,128 |
| vendor_dlkm_a | rothko 原厂 | 21,970,944 |
| system_dlkm_a | rothko 原厂 | 7,471,104 |
| odm_dlkm_a | rothko 原厂 | 348,160 |
- 合计 9,382,387,712B（8.74GiB），余量 260,317,184B；`G:\OriginOS_Work\04_build\v02_super.img` sha256 9C9C41F6…
### vendor_boot 补丁（toolsmith）
- `rothko_vendor_boot_patched.img` sha256 7847b5cc…：fstab.mt6989 删除全部 avb/avb_keys token（9461→9020B），cmdline 追加 `androidboot.selinux=permissive`；recovery fragment / dtb / header 结构自检 PASS
- 刷写顺序（安全策略）：
  1. 先刷 patched vendor_boot → `adb reboot recovery` 验证 vendor_boot 可加载（保证恢复通道）
  2. 再重启进系统（原 HyperOS system + patched vendor_boot）验证正常启动
  3. 最后刷 v02 super，测 vivo 系统首启
- 回滚：`/sdcard/work/flash/vendor_boot_stock.img`（原厂）、`v01_rothko_super.img`（原内容 super）均已备在设备上；PC 侧另有完整底包。

### 待观察风险（v0.2）
- vivo init.rc 会 import vivo 专有 rc（/init.vivo.rc、/vgc、/vendor/vgc 等），部分文件缺失 → 预期非致命
- vivo framework 依赖 vivo HAL（vendor.vivo.hardware.*，rothko vendor 无）→ 可能 system_server 异常
- 现有 /data 为 HyperOS 数据，OriginOS 首启可能因数据不匹配崩溃 → 必要时 format data
- 预期首个问题：SELinux permissive 已解除、AVB 已解除，剩余集中在 HAL/VINTF 与 props

## v0.2 首次 vivo 系统启动（2026-11-12 01:50 起）—— 已有重大进展，框架被 vivo 私有 HAL 卡住
### 结果
- super v02 刷入成功（dd 5.0s，首尾校验一致）
- **OriginOS 系统真实启动**：init → zygote → system_server → PackageManager 扫描完成（pms_ready）→ **开机动画正常播放**（1220x2712，HWC/gralloc 工作正常）
- 属性显示：ro.vivo.os.build.display.id=OriginOS 6、ro.vivo.os.version=16.0、ro.vivo.build.version.incremental=16.2.13.1.W10
- 但 system_server 每 ~60s 被 Watchdog 杀死 → zygote 重启 → 循环，sys.boot_completed 始终空
### 根因（Watchdog trace 精确定位）
/data/anr/traces_SystemServer_WDT*：main 线程阻塞在
libvivo_servers.so (android::getExtensionVibService+60)  → AServiceManager_waitForService → CppBackendShim::waitForService
调用链：VivoVibratorServiceImpl.<init> → VivoVibrationUtils.<init> → VibratorManagerService.<init> → SystemServer.startOtherServices(SystemServer.java:1858)
即：vivo 框架在 SystemServer 启动 VibratorManagerService 时，**阻塞等待 vivo 私有 RichTap 振动 HAL** endor.aac.hardware.richtap.vibrator.IRichtapVibrator，rothko vendor 没有该服务 → 永久阻塞 → Watchdog(60s) 杀 system_server。
### SELinux
- vendor_boot cmdline 的 androidboot.selinux=permissive 会被 vivo init 改回 Enforcing（audit: enforcing=1 old_enforcing=0）
- 已通过 KernelSU 模块 /data/adb/modules/portfix/post-fs-data.sh 在 post-fs-data 阶段执行 setenforce 0 → 验证生效（getenforce=Permissive），并让 crash_dump 可用（已能生成 tombstone）。
### 缺失 HAL 在 vivo vendor 中完整存在
/vendor/bin/hw/vendor.vivo.hardware.vibrator.custom.service
/vendor/lib64/vendor.aac.hardware.richtap.vibrator-V3-ndk.so
/vendor/lib64/vendor.aac.hardware.vibrator.custom.impl.so
/vendor/etc/init/vendor.vivo.hardware.vibrator.custom.service.rc
/vendor/etc/vintf/manifest/vendor.vivo.hardware.vibrator.custom.service.xml
手动启动时缺依赖 endor.vivo.hardware.vcode-V2-ndk.so（需连同依赖库一起补）。
### 下一步（二选一，优先 1）
1. **KSU 模块 overlay 注入 vivo 的 vibrator HAL 到 /system/vendor**（或 patch vendor 镜像），让该服务按 init 正常启动注册 → 解除 system_server 阻塞；这是"缺 vivo HAL 就补 HAL"的正路，后续其它 vivo 私有 HAL 同样处理。
2. 兜底：patch /system/lib64/libvivo_servers.so 的 getExtensionVibService 使其立即返回空（或 patch libbinder_ndk 的 waitForService），绕过阻塞。

## v0.2 取得关键成功：OriginOS 6 在 K70 Ultra 上正常开机进入桌面（2026-11-12 02:41）
### 结果（已验证）
- sys.boot_completed=1；SystemUI/launcher 正常；桌面截图 06_logs/v02_firstboot/screen_desktop.png
- 重启后仍直接进入锁屏/桌面（OOBE 已跳过并持久化，无 setup wizard）
- 显示：1220x2712，HWC/SurfaceFlinger 正常，帧率上报正常
- 触控：focaltech_ts 输入设备加载，触摸轴 0..1219.99 / 0..2711.99
- WiFi：wlan0 client mode、可扫描到 AP（cmd wifi list-scan-results 有结果）
- 移动网络：锁屏显示"中国移动 5G"，SIM=LOADED
- 音频：audioserver + audio HAL 正常（speaker 设备存在）
- 相机：cameraserver + camerahalserver running
- 传感器：50 个硬件传感器全部 running（sensorservice 正常）
- USB 调试：adb 可用，adb_enabled=1、development_settings_enabled=1、persist.sys.usb.config=adb
- Root：KernelSU 可用（su 正常）
### 解决的关键故障（全部有据可查）
1. **RichTap 振动 HAL 死等**：vivo SystemServer 在 VibratorManagerService 初始化时通过 libvivo_servers.so getExtensionVibService() 阻塞等待 vivo 私有 AIDL 服务 → Watchdog 60s 杀 system_server。
   修复：patch libvivo_servers.so 0x13ca0（getExtensionVibService）为 stp xzr,xzr,[x8]; mov x0,x8; ret，返回空 shared_ptr。KSU 模块 bind-mount 覆盖。
2. **sensorservice AIDL 断言崩溃**：vivo libsensorservice 对 rothko 传感器 HAL 的 Event payload tag 断言失败（Event.h:699 bad access）。
   修复：patch vivo libsensorservice.so 0x3fdac 处 BL __assert2 → NOP（正确 PLT 映射：plt(k)=0x74550+16k）。
3. **HyperOS 残留数据导致 system_server 崩溃**：AppOpService.opNameMapToOpSparseArray 解析到 "MIUI:10008"（Xiaomi 自定义 app-op）→ IllegalArgumentException。
   修复：清除 /data/misc{,_de/0}/apexdata/com.android.permission/access.abx*、/data/system/appops_accesses.xml、appops 历史（备份在 /data/local/tmp/portfix/data_backup）。
4. **SELinux**：vendor_boot cmdline 的 permissive 被 vivo init 改回 Enforcing → KSU 模块 post-fs-data setenforce 0。
### OOBE 跳过（第 1 项功能，已验证重启后持久）
- settings: global setup_skipped=1；secure setup_wizard_has_run=1 / setup_wizard_display=0
- persist.sys.wizard.setup=3
- set-home-activity com.bbk.launcher2/.Launcher
- pm disable-user --user 0 com.vivo.setupwizard
### 当前实现方式（迭代期）
- KSU 模块 /data/adb/modules/portfix/{post-fs-data.sh,module.prop} + /data/local/tmp/portfix/{libvivo_servers.so,libsensorservice_patched.so}
- 后续需把两个 lib patch 烧进 system 镜像、把 OOBE/USB 调试配置做成镜像级/首启自动，才能"清数据后仍开箱可用"

## v0.4 构建（用户指定修复项，2026-11-12 03:05）
按用户指导加入的修改（已打包进 super v04，等待刷入验证）：
1. **vivo 账号修复**：rothko /odm/etc/build.prop 中 o.product.odm.brand 与 o.product.odm.manufacturer 由 Xiaomi/Redmi 改为 **vivo**（odm 镜像 v03，864,448,512B，完整 1114 文件校验一致）。
2. **原子岛/状态栏高度**：从 rothko product 的 /product/overlay/ 取 DevicesAndroidOverlay.apk(16,892B) 与 DevicesOverlay.apk(23,757,406B)，加入移植包 vivo product 的 /product/overlay/（product 镜像 v03，409,948,160B）。
3. **关于本机**：vivo /system/build.prop 追加 o.vivo.internet.name=iQOO Neo9 Pro、o.vivo.market.name=iQOO Neo9 Pro（无 OEM 分区，故用 system build.prop；后续可补 OEM）。
4. 同时把 v0.2 的两个 lib patch 固化进 system 镜像（libvivo_servers.so / libsensorservice.so），删除 SetupWizard.apk，加入 /system/etc/init/portfix.rc + /system/etc/portfix_boot.sh（首启自动：开 USB 调试 + 跳过 OOBE + 写 adb_keys）。
super v04：9,663,676,416B，sha256=680CF23EA88B4098062AF2DE3EF1B84C492BCAA306EEA3D5DC86333C2758E2B6，余量 282,951,680B。
KSU 模块同步更新：post-fs-data 做 permissive + 一次性清理 HyperOS 残留权限状态；service.sh 一次性清 contacts/telephony provider（解决 android.process.acore 崩溃循环）。

## v0.6/v0.8 迭代（2026-11-12 03:20-04:30）
### 关键结论
1. **v06（system 重打包 + lib 补丁 + portfix rc，不改 product/odm）可以正常开机**（用户确认；之前误判为卡 logo 是首启慢+无 adb 无法观察）。
2. **卡 logo 的真凶：odm/product 镜像重打包丢了 SELinux 标签**
   - vivo/rothko 分区镜像重打包时用了错的 file_contexts 且未设 --mount-point：
     * system 应使用 plat_file_contexts + mount-point /（已正确）
     * odm 应使用 odm 自己的标签 + mount-point /odm
     * product 应使用 product 自己的标签 + mount-point /product
   - 错误重打包的 odm（v03/v04）所有文件变成 u:object_r:unlabeled:s0 → odm 挂载/服务失败 → 静态 logo。v04、v07a 卡 logo 均由此解释；v06 未动 odm/product 故正常。
3. 正确做法（已在 recovery 中实现）：挂载原始 odm，用 stat -c '%C' 采集原始每个文件的 SELinux 上下文，生成 file_contexts，mkfs.erofs 时 --mount-point=/odm --file-contexts=<生成的> 重建；验证 build.prop=vendor_configs_file、HAL 服务=各自 *_exec 域。
4. Android 侧重建 system 镜像可用：mkfs.erofs（手机 /system/bin 自带 1.8.3，recovery 内为 1.5 静态版，压缩选项较少）。
### 本轮构建物
- super v06（可开机基准）：sha256 6EE75EAA571365ACB1BF4AA37421C739FC5253942BC8DE2A4EE721EAC366136F
- super v07a（v06+odm v03 错误重打包）：卡 logo（已证实原因）
- super v08（v06 + odm v05 正确标签 & brand=vivo）：sha256 F0D3A6E13C1242D7A7018565F2682596B4456FEB90A1CE1CC43B18C5A69E4D4A，待验证
### 用户要求的功能落地情况
- **vivo 账号修复**：odm build.prop o.product.odm.brand/manufacturer=vivo（v08 已含，待 OOBE 验证）
- **原子岛/状态栏高度**：product/overlay 加入 rothko 的 DevicesAndroidOverlay.apk / DevicesOverlay.apk（已构建在 product v03，但因标签问题暂未合入 v08，待下一轮用正确标签重建 product 后加入）
- **关于本机**：system build.prop 已加 o.vivo.internet.name=iQOO Neo9 Pro、o.vivo.market.name=iQOO Neo9 Pro（v06 起已含）
- **USB 调试默认开启**：system build.prop 已加 persist.sys.usb.config=adb,mtp + portfix_early.sh 写 adb_keys/setprop；但 vivo 启动后 USB 仍未枚举，待进一步排查（可能需要 vivo 自己的 usb 属性或 ro.adb.secure/ro.debuggable）
- **跳过 OOBE**：/system/etc/init/portfix.rc + portfix_boot.sh（boot_completed 后 settings put setup_skipped/user_setup_complete + 禁用 SetupWizard）；当前 OOBE 因 vivo 账号卡住，v08 后应可继续

## v0.7 证据与修正（2026-11-12 05:00-05:20）
### 关键证据（pstore console，v08 bootloop）

[  596.868027] sync svc 16 invoked oom-killer: ... oom_score_adj=-1000
[  596.868164] 0 pages in swap cache
[  596.868165] Free swap  = 0kB
[  596.868167] Total swap = 0kB
[  596.868216] Out of memory and no killable processes...
[  596.868218] Kernel panic - not syncing: System is deadlocked on memory

- Mem-Info: unevictable:10463996kB（约 10.4GB 不可回收）、free 仅 ~38MB、all_unreclaimable? yes。
- **结论修正：卡 logo 重启的直接根因是 OOM 死锁 panic（完全没有 swap），不是 odm brand 改动。**
- rothko vendor /vendor/etc/init/hw/init.mt6989.rc 内部有 swapon_all /vendor/etc/fstab.enableswap（zram0, zramsize=100%, swapprio=10），但实测 Total swap=0 → 该调用未生效（可能 trigger 时机/属性依赖问题）。
- 之前"v06 能开机"是内存尚可的边界情况；bootloop 是 OOM panic 触发重启后循环。
### 另一个发现
- 我们放在 /system/etc/init/portfix.rc 的 exec 型 fixup 在 vivo init 下没有生效（/data/portfix.log 不存在，OOBE 没被跳过，USB 配置也没生效）。
- KSU 模块脚本同样没有执行：用户指出未安装 KSU manager app（ksud 未初始化）→ /data/adb/modules 不会被处理。所以修复必须做进镜像（init rc / build.prop），或先安装 KSU app。
### 工具进展
- **fastboot 已可用**（用户给 18D1:D00D 装了驱动）：astboot flash super 约 4 分钟，稳定，替代 recovery dd + 9.6GB 推包。
- 已确认 v06 super 可作可开机基准；odm 正确重打包方法（stat 采集原标签 + --mount-point=/omd）已验证标签正确（build.prop=vendor_configs_file、HAL=各自 exec 域）。
### 下一步计划（按优先级）
1. **修 zram/OOM**：system 镜像 portfix rc 用 init 内建写法启用 swap（write /sys/block/zram0/comp_algorithm + swapon_all /vendor/etc/fstab.enableswap），并改用 service ... start 模式执行脚本（替代不被解析的 exec）。
2. 重新验证 odm brand=vivo（内存问题修好后才能判断是否真的影响 vivo 账号）。
3. build.prop 默认 adb 开关（ro.debuggable/persist.sys.usb.config）；Android 侧 USB 不枚举问题需查 vivo USB HAL（后续可从 vivo vendor 拷 HAL/服务）。
4. OOBE 跳过：脚本机制修好后由 init service 执行（或安装 KSU app 后用模块）。

## v0.8 突破：v12 成功进入 OriginOS 桌面（2026-11-12 06:20）
### 关键修复（两个都是 pstore 日志定位的）
1. **OOM deadlock panic**：v10 起在 system 的 /system/etc/init/portfix.rc 用 init 内建写 zram：
   on late-init: write /sys/block/zram0/comp_algorithm lz4 ...、on post-fs-data: swapon_all /vendor/etc/fstab.enableswap，
   并在 portfix_early.sh 里做 mkswap/swapon 兜底 → 不再出现 Total swap=0kB / Kernel panic - not syncing: System is deadlocked on memory。
2. **apexd-bootstrap 失败导致无限重启**：v11 的 pstore 显示
   pexd-bootstrap: Failed to collect APEX keys : Can't open /odm/apex for reading : Permission denied
   Service apexd-bootstrap has 'reboot_on_failure' option and failed, shutting down system
   eboot,reason=reboot,bootloader,bootstrap-apexd-failed。
   根因：我们重打包的 odm 镜像 **根目录 SELinux 标签是 unlabeled**（原厂是 u:object_r:vendor_file:s0），并且 /odm/apex 在原厂 odm 中根本不存在，apexd 扫描时在根目录上被 SELinux 拒绝。
   修复：生成 odm file_contexts 时加入根路径规则 /odm u:object_r:vendor_file:s0，mkfs 用 --mount-point=/odm 重建（odm v06）。验证 ROOT: vendor_file、build.prop: vendor_configs_file。
### v12 内容（super sha256 1ADF216C61B6A6C069D3FC698F614E5A62EBA235F003D5E9A5D934AAE1C31FCD）
- system v11：vivo system + 已注入 libvivo_servers/libsensorservice 补丁 + 移除 SetupWizard + build.prop 加
  persist.sys.usb.config=adb,mtp / ro.setupwizard.mode=DISABLED / ro.debuggable=1 / service.adb.root=1 / ro.adb.secure=0 /
  ro.vivo.internet.name=iQOO Neo9 Pro / ro.vivo.market.name=iQOO Neo9 Pro
- odm v06：rothko odm + ro.product.odm.brand/manufacturer=vivo + 完整 SELinux 标签
- 其他分区保持 rothko 原厂（vendor/system_ext( vivo)/mi_ext/dlkm）+ vivo product 原厂
- **用户确认：v12 已进入桌面** ✅
### 待办
- USB adb 仍不枚举（Android 侧），需排查 vivo USB HAL / adb_enabled；如果用户能手动开 USB 调试更好。
- product overlay（DevicesAndroidOverlay.apk / DevicesOverlay.apk）尚未合入（product 需用正确标签重建）。
- 验证三项用户修复：vivo 账号登录、关于本机型号、原子岛/状态栏高度。

## v0.9 收尾：回滚 v12 + 交接文档（2026-08-12 09:20）
### 本轮实验与结论（v13–v18）
- **v13**：把 vivo 的 init.usb.rc/init.usb.configfs.rc 换成 rothko 原厂 → settings 崩、bug 增多（方向错误，已撤回）。
- **v14/v15**：修 persist.sys.usb.config 顺序（mtp,adb）、在 init.usb.rc 追加 start adbd + TCP 5555 → 能开机，但 adbd 未监听、settings 崩。
- **v16**：plat_sepolicy.cil 里给全部收集到的 type 加 (typepermissive) → 无限重启（vendor/odm 定义的 type 写进 plat 编译失败）。
- **v17**：按分区拆分 typepermissive（plat 1894 条 / vendor 3264 条）→ 仍无限重启（CIL 仍编译失败或 init 拒绝重编策略）。
- **v18**：在 vivo init.usb.rc 追加 on post-fs-data: exec u:r:su:s0 root root -- /system/bin/sh /system/etc/portfix_perm.sh（脚本 setenforce 0）→ settings 崩、adb/基带未恢复。
- **selinux=0（内核 cmdline）**：init 能跑但 zygote 起不来 → 卡开机动画，**不可用**。
### 有效结论
1. OOM deadlock（zram swap 未启用）与 apexd-bootstrap 失败（odm 根目录 unlabeled）已修复并验证。
2. init 域无法执行自建 rc 里的 exec/service（/data/portfix_*.log 全部未生成）；vivo 自己用 exec u:r:su:s0 ... -- 模式（simpleperf.rc），但 v18 沿用该模式仍未生效。
3. 基带/USB/开发者选项同时坏，与早期 v02（KSU 模块 permissive 时 adb+基带正常）对比，最强嫌疑是 **SELinux Enforcing**。
4. 换 usb.rc 会破坏 vivo 框架 → 不要走这条路。
### 交付
- 已回滚刷入 **super v12**（可进桌面、OOBE 已跳过、settings/关于手机正常）。
- 已写  7_docs/STATUS_2026-08-12_HANDOVER.md：设备基线、证据、根因、构建/刷机 SOP、镜像资产清单、下一轮 P0–P4 计划、回滚方法。

## v0.10 收尾验证（2026-08-12 09:12）
- 刷 v12 super 后执行 fastboot -w 干净启动：用户确认 **桌面正常、设置能打开、关于手机正常** → 之前 settings 崩是 /data 跨版本残留导致，非镜像问题。
- 交付： 7_docs/STATUS_2026-08-12_HANDOVER.md（含全部证据、根因、SOP、资产、P0–P4 计划、回滚）。
- 待办（下一轮）：adb/USB(MTP) + 基带（怀疑 SELinux Enforcing）；vivo 账号登录；开发者选项；product overlay 验证。

## v0.11 v25/v26：功能收尾（2026-08-12 11:20-11:55）
- v25：model props=Redmi K70 Ultra；init service 开机自动化（自动开 USB 调试 + 跳过 OOBE），两项分别重置→重启验证通过；USB adb 正常。
- v26：product overlay（rothko DevicesAndroidOverlay/DevicesOverlay）合入，cmd overlay list 显示两个 overlay 已启用；设置正常。
- 相机：media.camera 未注册（vivo 私有相机栈），用户确认移植包不要求 vivo 相机。
- GitHub 仓库已建立并推送（private）：https://github.com/ikun514/OriginOS-Rothko-Port

## v0.12 v27/v28：卡顿与相册根因（2026-08-12 12:00-12:50）
- 卡顿根因：odm 里小米 endor.xiaomi.sensor.citsensorservice.aidl 99% CPU 空转（loadavg 918）；odm v08 删除该 rc 后 loadavg 降到 10~25。
- 相册/媒体根因：vold 启动崩溃（Check failed: android::vold::sBlkidContext != nullptr，系统中缺 libblkid.so）→ 外部存储卷未挂载 → MediaStore Volume external_primary not found → 相册线程风暴 + 系统级崩溃；workaround db shell sm mount emulated;0 可用。
- 已暂停排障，按用户要求同步 GitHub 并制作 G 盘体验包（super v28 + patched vendor_boot + adb/fastboot + flash_all.bat）。
