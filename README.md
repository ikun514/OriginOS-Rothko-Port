# OriginOS 6 (vivo PD2339) → Redmi K70 Ultra (rothko) 移植工程

将 vivo OriginOS 6 / Android 16（PD2339 = iQOO Neo9 Pro / Neo9S Pro，MT6989）移植到
Redmi K70 Ultra（rothko，MT6989，HyperOS 3.0.303 / Android 16）的完整工程记录：
脚本、镜像构建工具、刷机流程、故障诊断日志、根因分析与状态文档。

> ⚠️ 本仓库**不包含任何 ROM 镜像/固件大文件**（`*.img`、super、vendor_boot 等被 .gitignore 排除），
> 只包含脚本、文档、日志与小的二进制补丁。镜像需要按文档中的流程从你自己的固件包生成。

## 当前状态（2026-08-12）

- ✅ 正常开机进 OriginOS 桌面（super v25）
- ✅ 触控 / 显示（1220x2712）
- ✅ Wi-Fi（可连接）
- ✅ 蓝牙（可开启，状态 ON）
- ✅ 移动网络 / 基带（中国移动 5G NR_SA，RSRP -96）
- ✅ 音频（AudioService/HAL 正常）
- ✅ 相机（camera provider HAL 正常注册）
- ✅ 传感器（50 个 h/w 传感器运行中）
- ✅ **USB 调试（adb over USB）可用**
- ✅ OOBE 已跳过（移除 SetupWizard + boot 自动化写 settings）
- ✅ 自动开启 USB 调试（镜像级 init service 在 boot_completed 写 settings）
- ✅ 关于本机型号显示真实值 `Redmi K70 Ultra`（ro.vivo.internet.name / ro.vivo.market.name）
- ✅ vivo 账号可登录（odm brand=vivo + SELinux permissive）
- ⚠️ MTP 文件传输仍不可用（vivo 的 vusbd 与本移植的 USB 组合二选一，当前使用 adb-only 组合）
- ⚠️ 状态栏/原子岛高度 overlay 已构建（product v05）但尚未合入验证

### 全链路验证命令

```bash
adb shell getprop sys.boot_completed      # 1
adb shell getenforce                       # Permissive
adb shell getprop ro.vivo.market.name      # Redmi K70 Ultra
adb shell settings get global adb_enabled  # 1
adb shell dumpsys telephony.registry | grep mServiceState   # 中国移动 / NR_SA
adb shell dumpsys sensorservice | head     # 50 h/w sensors
adb shell cmd bluetooth_manager enable && adb shell dumpsys bluetooth_manager | head   # enabled: true
```

## 关键根因与修复（踩坑记录）

| 现象 | 根因 | 修复 |
|---|---|---|
| 卡 logo 无限重启 | zram swap 未启用 → `Total swap=0kB` → `Kernel panic: System is deadlocked on memory` | system 镜像 `/system/etc/init/portfix.rc`：`write /sys/block/zram0/comp_algorithm lz4` + `swapon_all /vendor/etc/fstab.enableswap` |
| 无限重启（apexd） | 重打包 odm 根目录 SELinux 标签 `unlabeled` → `apexd-bootstrap: Can't open /odm/apex: Permission denied` → reboot_on_failure | odm 重打包时 file_contexts 加根规则 `/odm u:object_r:vendor_file:s0` + `--mount-point=/omd`(=/odm) |
| 基带/开发者选项/vivo 账号全坏 | SELinux Enforcing 拦了 modem/RIL HAL、Settings、账号服务 | 镜像级 permissive：plat_sepolicy.cil 加两条 `allow`，init.usb.rc `on early-init: write /sys/fs/selinux/enforce 0` |
| USB 不枚举 | vivo 框架设 `sys.usb.config=charging,adb`，MTK vendor rc 只认 `mtp,adb`/`adb`；且 mtp 需要 `vendor.usb.ffs.mtp.ready` | 用 rothko 原机 `init.usb.rc`/`init.usb.configfs.rc` 替换，并把 charging 重映射为 **adb-only** 组合（adb 只需 `sys.usb.ffs.ready`，由 adbd 提供） |
| 设置打不开 | /data 残留了不同 system 版本的 settings/DB | `fastboot -w` 清 /data |
| init 域 exec 脚本不生效 | init 域无 execute shell 权限 | 用 `seclabel u:r:su:s0` 的 service（rc 里 `/system/etc/init/hw/init.usb.rc` 追加） |

## 目录结构

```
scripts/            构建、刷机、诊断脚本（.sh 在设备端执行，.ps1/.py 在 PC 端）
  toolchain/        super 打包(make_super.py)、vendor_boot patch(patch_vendor_boot.py)、lpdump 等
05_flash/portfix/   注入到 system 镜像的 fixup（portfix.rc/early/boot/diag 脚本）
06_logs/            迭代日志、工程日志、pstore/tombstone 证据
07_docs/            计划、状态交接文档
02_base/lib*.so     对 vivo 框架库的二进制补丁（小文件，已入库）
```

## 构建流程（摘要，详见 07_docs/STATUS_2026-08-12_HANDOVER.md）

设备端（Android root 或 recovery，需 `mkfs.erofs`）：

```sh
mount -t erofs -o ro base_system.img /mnt
cp -a /mnt/. /data/tree/
# 修改 /data/tree/... 后：
mkfs.erofs -zlz4hc,level=9 --file-contexts=plat_file_contexts -T 0 out.img /data/tree
# 其他分区必须带 --mount-point=/odm | /vendor | /product，且 file_contexts 逐文件采集原标签
```

PC 端组装 super 并刷入：

```powershell
.\scripts\build_super_v06.ps1 -SystemImage system.img -VendorImage vendor.img `
  -ProductImage product.img -OdmImage odm.img -Out vNN_super.img
fastboot flash super vNN_super.img
fastboot -w       # 需要干净 /data 时
fastboot reboot
```

## 刷机/救援

- Bootloader fastboot 可用（Windows 需装驱动，设备在 fastboot 模式显示 `VID_18D1&PID_D00D`）
- OrangeFox recovery：长按电源 15 秒 → 音量上+电源；recovery adb 可抓
  `/sys/fs/pstore/console-ramoops-0`（内核/init 崩溃日志）
- 回滚：`fastboot flash super <v12_super.img>`（首个可用桌面版本）或原厂 super

## 文档

- [状态交接文档](07_docs/STATUS_2026-08-12_HANDOVER.md)：完整证据链、根因、SOP、资产清单、下一步
- [迭代日志](06_logs/ITERATION_LOG.md)：每次构建改了什么、结果如何
- [工程日志](06_logs/ENGINEERING_LOG.md)
- [计划](07_docs/PLAN.md)

## 许可 / 声明

本项目仅用于个人设备研究与学习。移植涉及的所有原厂固件版权归各自厂商（vivo / 小米）所有，
仓库不包含任何厂商固件或 ROM 镜像。请自行持有合法固件并遵守当地法律与设备保修条款。
