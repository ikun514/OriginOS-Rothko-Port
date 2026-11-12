# 移植总体方案（PLAN）

## 目标
vivo OriginOS 16（PD2339 = iQOO Neo9 Pro，mt6989/天玑9300，Android 16，vfs=erofs）
→ Redmi K70 Ultra（rothko，mt6989/天玑9300+，HyperOS3/Android16，super 9.0GiB）

## 架构决策（底包 + 移植包）
- **底包（rothko 原厂，全部 adb 提取）**：boot(kernel) / init_boot(KSU) / vendor_boot(platform ramdisk+dtb+OrangeFox recovery fragment) / dtbo / vbmeta* / vendor / odm / vendor_dlkm / system_dlkm / odm_dlkm / mi_ext
- **移植源（vivo PD2339 A16 全量包）**：system / product / system_ext（vivo 框架与 OriginOS UI），odm/vendor 仅作参考比对，**不整体替换** rothko vendor（内核模块必须与 rothko kernel 匹配）
- 内核/DTB/面板/触控/PMIC/modem 等硬件适配完全沿用 rothko 原厂

## 分区尺寸预算（super 上限 9,663,676,416B）
| 项 | 大小 | 处置 |
|---|---|---|
| vivo system | 7,934,083,072 | **必须精简到 ≤ ~6.0GB** |
| vivo product | 393,981,952 | 保留（替换 rothko product 4.48GB） |
| vivo system_ext | 411,910,144 | 保留 |
| rothko vendor | 1,644,707,840 | 保留 |
| rothko odm | 881,057,792 | 保留（面板/触控/相机/热配置） |
| rothko vendor_dlkm | 21,970,944 | 保留（内核模块） |
| rothko system_dlkm | 7,471,104 | 保留 |
| rothko odm_dlkm | 348,160 | 保留 |
| rothko mi_ext | 126,640,128 | 视 fstab overlay 需求决定是否保留（nofail） |
合计（含 mi_ext）≈ 3.22GiB + system ≤ 8.95GiB ⇒ **vivo system 需精简 ≥1.6GiB**

## 关键改动点（按优先级）
1. **AVB/SELinux**：刷 `vbmeta` 时 `--disable-verity --disable-verification`；vendor_boot cmdline 追加 `androidboot.selinux=permissive`（并准备 init 里 setenforce 兜底）
2. **super 重建**：scripts/toolchain/make_super.py（mtk 布局，10.2 元数据），group main_a，分区单 extent
3. **fstab**（vendor_boot ramdisk 内）：按新布局保留 erofs/ext4 双行；如去掉 mi_ext 则同步删除 overlay 段
4. **VINTF/兼容矩阵**：vivo system 的 compatibility matrix 要求 vivo vendor HAL（vendor.vivo.hardware.*），rothko vendor 没有 → 需按 logcat 报错逐项处理（优先保留 vivo vendor 侧 jar/hal 客户端 stub 或改 matrix）
5. **props**：对齐 ro.product.* / ro.build.* / ro.vendor.*；保留 vivo 的 ro.vivo.*
6. **SELinux 策略**：首轮 permissive 启动，拿到 avc 后再决定是否补 policy
7. **OOBE 与 USB 调试**：系统能进桌面后再做，分两次修改分别验证

## 闪机方式
- 优先 fastbootd：`fastboot flash super super.img`（重建后的整包）
- 或 fastbootd 内逐分区 flash（需先 resize-logical-partition，且组内余量仅 0.588GiB，通常不可行 → 以整 super 为主）
- 备份/回滚：`02_base/images/rothko_current_*.img` + 一键回滚脚本（刷回原 super/boot/vendor_boot/vbmeta）

## 日志采集（每次失败）
1. fastboot/recovery 下 `dmesg`、`/proc/last_kmsg`?（MTK: `cat /proc/last_kmsg` 或 pstore/ramoops）
2. OrangeFox 下 `adb shell` 取 `/tmp/recovery.log`、`/sys/fs/pstore/*`
3. 若进到 Android 引导阶段：`adb logcat -b all -d`（需尽早 adb 起来）
4. 统一存 `06_logs/YYYYmmdd_HHMM_<版本>/`
