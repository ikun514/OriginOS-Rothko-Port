# OriginOS → Redmi K70 Ultra (rothko) 移植工程日志

## 0. 工程信息
- 项目根目录：`C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port`
- 目标机：Redmi K70 Ultra，codename `rothko`，型号 2407FRK8EC，SoC **mt6989（天玑9300+）**
- 目标机系统：HyperOS 3.0.303.0.WNNCNXM，Android 16（SDK 36），A/B + 虚拟动态分区（super 9.0 GiB），BL 已解锁（`ro.boot.verifiedbootstate=orange`）
- 目标机 root：KernelSU（init_boot 已打补丁，含 kernelsu.ko/init.real），Recovery：OrangeFox 位于 vendor_boot
- 移植源（正确平台）：vivo **PD2339 = iQOO Neo9 Pro / Neo9S Pro（天玑9300，mt6989）**，OriginOS 16（Android 16）
- 工具：platform-tools 37.0.1（`tools\platform-tools`）、Python 3.12（pip 装好 lz4/brotli/zstandard/protobuf 于 `00_tools\pylibs`）
- 本机限制：Windows 11 LTSC，无 WSL/HyperV（未启用，不能重启），无 java/7z/git；一切镜像处理走 Python + 手机端 aarch64 工具

## 1. 用户提供的源 ROM
| 文件 | 平台 | 版本 | 类型 | 结论 |
|---|---|---|---|---|
| `202609082329015227bea0f9c421d684e20ce35d70d0b9.zip`（4.13GB） | PD2339（mt6989） | 15.1.16.0.W10 → **16.2.13.1.W10** | **增量 OTA**（BROTLI_BSDIFF/SOURCE_COPY） | 平台正确，但需 15.1.16.0 全量基线才能还原 |
| `20260909201919d25acc073cbe9d441a2063fdc89cc26e.zip`（9.32GB） | **PD2403（高通骁龙8Gen3）** | 16.2.16.1.W10 | 全量包（REPLACE_ZSTD） | **平台不匹配**（分区为 abl/aop/cpucp/xbl/tz/uefi…），不能作为 MTK 移植源 |

增量包 payload 版本：system 7,934,083,072 / vendor 3,135,754,240 / product 393,981,952 / system_ext 411,910,144 / odm 4,780,032 / system_dlkm 14,913,536 / vendor_dlkm 45,801,472（合计 ≈ 11.94 GB）
PD2403 全量包对比：system 8,575,733,760 / vendor 2,803,974,144 / product 402,694,144 / system_ext 266,346,496 / odm 22,286,336（合计 ≈ 12.07 GB）

## 2. 底包（rothko 原厂）提取清单（全部经 adb su dd 提取）
| 分区 | 大小(字节) | 文件 |
|---|---|---|
| super | 9,663,676,416 | `02_base/images/rothko_current_super.img` |
| boot_a | 67,108,864 | `rothko_current_boot_a.img`（header v4，kernel 16,547,799B，lz4-legacy，ramdisk=0） |
| init_boot_a | 8,388,608 | `rothko_current_init_boot_a.img`（v4，ramdisk 3,629,953B lz4-legacy，含 KSU） |
| vendor_boot_a | 67,108,864 | `rothko_current_vendor_boot_a.img`（v4，2 fragments：platform 36,310,343B gzip / recovery 26,107,020B gzip=OrangeFox；dtb 444,690B） |
| dtbo_a | 8,388,608 | `rothko_current_dtbo_a.img` |
| vbmeta_a / vbmeta_system_a / vbmeta_vendor_a | 8,388,608 各 | `rothko_current_vbmeta*_a.img` |
| misc / metadata | 524,288 / 77,561,856 | `rothko_current_misc.img` / `rothko_current_metadata.img` |
| vendor_a | 1,644,707,840 | `rothko_current_vendor_a.img` |
| odm_a | 881,057,792 | `rothko_current_odm_a.img` |
| system_a | 879,894,528 | `rothko_current_system_a.img` |
| system_ext_a | 936,296,448 | `rothko_current_system_ext_a.img` |
| mi_ext_a | 126,640,128 | `rothko_current_mi_ext_a.img` |
| vendor_dlkm_a | 21,970,944 | `rothko_current_vendor_dlkm_a.img` |
| system_dlkm_a | 7,471,104 | `rothko_current_system_dlkm_a.img` |
| odm_dlkm_a | 348,160 | `rothko_current_odm_dlkm_a.img` |

### super (lp metadata v10.2) 关键数据
- 物理总大小 9,663,676,416；group `main_a`/`main_b` max=9,653,190,656；logical_block=4096
- Slot A 已用：product_a 4,478,963,712 / vendor_a 1,644,707,840 / system_ext_a 936,296,448 / odm_a 881,057,792 / system_a 879,894,528 / mi_ext_a 126,640,128 / vendor_dlkm_a 21,970,944 / system_dlkm_a 7,471,104 / odm_dlkm_a 348,160 = **8,977,350,656（8.36 GiB）**，剩余 ≈ 686 MB
- Slot B 的分区元数据存在但 size=0（虚拟 A/B + userspace snapshot）

## 3. 基底 fstab（vendor_boot 内 first_stage_ramdisk/fstab.mt6989）要点
- system/system_ext/product: `erofs` 或 `ext4`，`avb=vbmeta_system`（含 GSI avb_keys）
- vendor/odm/vendor_dlkm/odm_dlkm/system_dlkm: erofs 或 ext4，`avb`
- mi_ext: erofs/ext4，`avb=vbmeta`，并有大量 overlay（product/*、system/*、system_ext/etc/permissions）
- metadata: f2fs；data: f2fs + fileencryption aes-256-xts
- 结论：**把对应分区换成 ext4 在 fstab 层面是允许的**（每种挂载点都有 erofs/ext4 两行）

## 4. 关键约束与决策
1. **super 硬上限 9.0 GiB**，而 vivo 12GB 系镜像无法整体放入 → 必须"精简 vivo 侧 + 保留 rothko 侧必要件"组合，并重新生成 super（lpmake）或在 fastbootd 中按新尺寸 flash。待定方案见 `07_docs/PLAN.md`。
2. 高通平台包（PD2403）不能用于 MTK 移植；必须等 PD2339（mt6989）全量包，或用 PD2339 增量包 + 15.1.16.0 全量基线还原。
3. 内核侧保持 rothko 原厂：boot(kernel) / init_boot / vendor_boot / dtbo / dtb 不动（面板、触控、PMIC、modem 全靠这一套）。
4. AVB：BL 已解锁，刷机时用 `fastboot --disable-verity --disable-verification flash vbmeta` 或直接刷修改版 vbmeta，规避签名校验。
5. 修改镜像的 SELinux 标签：在手机端 loop 挂载 + restorecon 处理；erofs 打包用 recovery ramdisk 里的 `mkfs.erofs`（aarch64）。

## 5. 历史失败/无效方案记录
（暂无，随调试更新）

## 6. 下一步
1. 用户提供 PD2339（mt6989）Android 16 全量包（或 15.1.16.0 全量基线）。
2. 提取 vivo system/product/system_ext/odm/vendor 镜像 → 分析 VINTF/HAL/init/props/sepolicy 与 rothko 的差异。
3. 制定 super 构建方案（尺寸预算）→ 首次刷机 → 抓 logcat/dmesg/OrangeFox 日志 → 迭代。

## 7. 硬件/工具链重要事实（2026-11-12 01:10）
- **OrangeFox 的 fastbootd 是坏的（用户确认）**：不要用 db reboot fastboot/fastbootd 刷机，会卡在 fastbootd 且 Windows 无 USB 驱动（VID_2717&PID_4EE0 显示 Error）。
- 刷机通道改为：**OrangeFox recovery（vendor_boot 内）adbd + adb shell dd 直写分区**，或 recovery 刷 zip；必要时用户手动进 bootloader fastboot。
- 手机/PC 权限：Windows 当前用户是 Administrator（可装驱动），但没有 fastbootd 驱动；adb 正常（Android/recovery 模式）。
- 用户在每次刷机后可协助把手机弄进 recovery/fastboot。
