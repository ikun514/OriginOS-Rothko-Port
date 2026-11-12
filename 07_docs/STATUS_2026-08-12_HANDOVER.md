# OriginOS → Redmi K70 Ultra 移植 · 现状交接文档

生成时间：2026-08-12 09:15（Asia/Shanghai）
当前刷入版本：**super v12（最佳可用版本）**

---

## 1. 设备与固件基线

| 项 | 值 |
|---|---|
| 目标机 | Redmi K70 Ultra（代号 rothko，型号 2407FRK8EC），MT6989 Dimensity 9300+ |
| 原厂基底 | HyperOS 3.0.303.0.WNNCNXM / Android 16 / SDK 36 / A/B + virtual A/B / super 9,663,676,416 B |
| Bootloader | 已解锁（`verifiedbootstate=orange`） |
| Recovery | OrangeFox（内嵌在 vendor_boot；**fastbootd 坏**，但 bootloader fastboot 可用） |
| Root | KernelSU（init_boot 已 patch），**但 /data 多次清空 → KSU manager app 与模块数据已不存在** |
| 源固件 | vivo PD2339 = iQOO Neo9 Pro / Neo9S Pro（mt6989），OriginOS 6 / Android 16 / `16.2.13.1.W10.V000L1`（全量包） |
| 刷机通道 | **bootloader fastboot 可用**（Windows 已装驱动 Android Bootloader Interface，VID_18D1&PID_D00D）。`fastboot flash super` 约 4 分钟；recovery adb 也可用（dd + pstore 抓日志） |

### 已刷入的设备级改动
1. `vendor_boot`：`G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img`
   - 删除 first_stage fstab 里所有 AVB token（`avb`/`avb=`/`avb_keys=`）
   - cmdline 追加 `androidboot.selinux=permissive`（注意：**vivo init 会覆盖成 Enforcing**，仅作记录）
   - 保留了 AVB footer（签名不匹配，但 BL 已解锁可启动）
2. `init_boot`：KSU patch 版（root 能力还在；模块执行依赖 /data/adb/ksu，已随清数据丢失）
3. `super`：当前 = v12（见第 5 节）

---

## 2. 当前可用状态（v12 用户实测）

工作正常：
- OriginOS 6 开机 → 桌面 ✓
- OOBE 已跳过（自动进桌面）✓
- 设置 → 关于手机 可打开（型号显示 Redmi K70 Ultra）✓
- Wi-Fi 可连接 ✓
- vivo 账号页面可以打开（登录失败，见 3.4）
- 传感器 50 个、音频/相机 HAL 在线（v02 时期实测）

未解决（用户反馈）：
- 基带（无信号/基带未知）
- USB 调试 / MTP（Android 侧 USB 完全不枚举，连 MTP 都没有）
- 开发者选项：列表能进，但点进页面就崩
- vivo 账号登录失败
- “关于手机”要求显示真实硬件数据（目前型号已是 Redmi K70 Ultra，其它字段待核对）

---

## 3. 已知问题的证据与根因分析

### 3.1 早期“卡 logo / 无限重启”的真正原因（已解决）
pstore console（v08 那次）：

```
[  596.868027] sync svc 16 invoked oom-killer: ... oom_score_adj=-1000
[  596.868164] 0 pages in swap cache
[  596.868165] Free swap  = 0kB
[  596.868167] Total swap = 0kB
[  596.868216] Out of memory and no killable processes...
[  596.868218] Kernel panic - not syncing: System is deadlocked on memory
```
- Mem-Info 显示 `unevictable:10463996kB`（约 10.4GB 不可回收）、free 仅 ~38MB。
- 根因：**zram swap 从未启用**。rothko vendor 的 `/vendor/etc/init/hw/init.mt6989.rc` 里虽然有
  `swapon_all /vendor/etc/fstab.enableswap`（zram0, zramsize=100%, swapprio=10），但在 vivo init 下没生效。
- 修复（已并入 v10+）：system 镜像里 `/system/etc/init/portfix.rc` 用 init 内建：
  ```
  on late-init
      write /sys/block/zram0/comp_algorithm lz4
      write /proc/sys/vm/page-cluster 0
      write /proc/sys/vm/swappiness 120
  on post-fs-data
      swapon_all /vendor/etc/fstab.enableswap
  ```
  并在 `portfix_early.sh` 里做 `mkswap/swapon` 兜底。
- 验证：后续启动日志出现 `init: VmSwap: ...`、`init: zram closing, normal swapoff path`，不再 OOM panic。

### 3.2 v11 无限重启 → apexd-bootstrap 失败（已解决）
```
apexd-bootstrap: Scanning /odm/apex for pre-installed ApexFiles
apexd-bootstrap: Failed to collect APEX keys : Can't open /odm/apex for reading : Permission denied
Service apexd-bootstrap has 'reboot_on_failure' option and failed, shutting down system
init: Got shutdown_command 'reboot,bootloader,bootstrap-apexd-failed'
```
- 根因：**我们重打包的 odm 镜像根目录 SELinux 标签是 `unlabeled`**（原厂是 `u:object_r:vendor_file:s0`），
  且 `/odm/apex` 在原厂 odm 中本来就不存在，apexd 扫描时在根目录被 SELinux 拒绝 → 致命 → reboot_on_failure。
- 修复：重打包 odm 时生成 file_contexts 加根路径规则 `/odm u:object_r:vendor_file:s0`，
  且必须 `--mount-point=/odm`（product 用 `/product`，vendor 用 `/vendor`）。
  已产出并验证 **odm v06 / v07**（品牌已改 vivo，标签正确）。

### 3.3 `selinux=0`（内核级关闭 SELinux）不可行
- 我们给 vendor_boot cmdline 加 `selinux=0` 后实测：init 正常、surfaceflinger/vold/adbd 都起来了，
  但 **zygote 依赖 SELinux 设置 app 上下文 → 起不来 → 卡开机动画**。
- 结论：只能做 **Permissive（加载策略但不强制）**，不能 SELinux disabled。

### 3.4 当前的三大问题（基带 / USB / 开发者选项）最可能根因
**关键线索：早期 v02 版本（系统 = vivo system v03 + 原厂 odm/product + `KSU 模块在 /data` 里 setenforce 0）
时，adb 与基带都是正常的（用户确认 5G 中国移动可用）。后来允许清数据 → 模块消失 → SELinux 回到 Enforcing
→ 基带/HAL/USB 全被拦。**

- 基带：vendor 的 modem/RIL HAL 域（`ril-daemon-mtk`、`ccci_mdinit`、`hal_*modem*`）被 SELinux 拒绝访问；
  内核 pstore 里 modem/ccci 初始化是成功退出的（`Service 'ccci_mdinit' exited with status 0`），
  所以不是固件问题，更像 HAL 运行期权限。
- USB/MTP：vivo 框架的 USB 栈是 vivo fork（`service vusbd /system/bin/vusbd`、`sys.usb.configfs`、
  `vendor.sys.usb.adb.disabled` 等），与标准 AOSP `init.usb.rc` + MTK configfs 有差异；
  我们曾把 rothko 的 `init.usb.rc`/`init.usb.configfs.rc` 替换进 vivo system（v13），
  结果 **settings 开始崩、MTP 更坏** → 方向错误，已回退。当前 v12 不替换这两个文件。
- 开发者选项崩溃：需要 logcat/Java 堆栈，目前拿不到（adb 不通）。
- vivo 账号登录失败：需要网络/TEE 侧日志；brand 已改 vivo（odm），账号页能打开但登录失败。

### 3.5 init 域无法执行脚本（重要限制）
- 放在 `/system/etc/init/portfix.rc`（新文件）里的 `exec` / `service` 全部没有执行：
  `/data/portfix_early.log`、`/data/portfix_boot.log`、`/data/portfix_perm.log` 从未生成，
  OOBE 自动跳过、adb_enabled、setenforce 也从未发生。
- 推断：**init 域没有 execute shell/script 的 SELinux 权限**（AOSP 默认 init 不能 exec shell）。
- 反证：vivo 自己的 `/system/etc/init/simpleperf.rc` 用的是
  `exec u:r:su:s0 root root -- /system/bin/simpleperf ...`，说明 **init 通过 `exec u:r:su:s0 ... --` 可以执行**。
- v18 尝试：在 vivo 的 `/system/etc/init/hw/init.usb.rc` 末尾追加
  `on post-fs-data: exec u:r:su:s0 root root -- /system/bin/sh /system/etc/portfix_perm.sh`
  （脚本内 setenforce 0）。v18 仍表现为 settings 崩、adb/基带不通 → 该 exec 可能仍失败，或 su 域不足以 setenforce。
- 策略里发现：`(type su)` 存在；`vivodebug_plat_sepolicy.cil` 里有 `(typepermissive su)`（vivo 调试策略），
  但 **ro.debuggable=1 时 vivo 是否真的加载 vivodebug 策略尚未确认**。

### 3.6 关于“真实数据”
- 当前 system build.prop 已设置：
  `ro.vivo.internet.name=Redmi K70 Ultra`、`ro.vivo.market.name=Redmi K70 Ultra`
  （v18 前是 `iQOO Neo9 Pro` 占位值）。
- 其余“真实数据”（SoC/内存/存储/序列号等）来自 rothko 的 system/vendor/odm 原厂 props，理论上已经是真实值；
  用户看到哪些字段不对，需要截图逐项核对（About 页字段大多来自 `ro.product.*`、`ro.vivo.*`、`ro.soc.*`）。

### 3.7 状态栏/原子岛高度 overlay（用户需求 #2）
- 已从 rothko product 的 `/product/overlay/` 取出 `DevicesAndroidOverlay.apk`(16,892 B) 与
  `DevicesOverlay.apk`(23,757,406 B)。
- 已构建 **product v05**（vivo product + 这两个 overlay，product 标签正确、mount-point=/product），
  在 v13 里合入过，但用户反馈“这个版本多了一堆 bug”（同时 v13 也换了 usb.rc，无法归因）。
- **建议单独回归验证**：v12 基线 + 只加 product v05（不动 usb.rc、不动 system）看 settings 是否还正常、
  高度是否变化。

---

## 4. 构建与刷机 SOP（已验证可用）

### 4.1 分区镜像重打包（设备端，recovery/adb root 或 Android root）
```sh
# 1) 挂载原镜像
mount -t erofs -o ro /data/local/tmp/orig.img /mnt/x
# 2) 拷贝树
cp -a /mnt/x/. /data/local/tmp/tree/
# 3) 生成该分区专属 file_contexts（从原镜像逐文件采集标签）
printf '/odm u:object_r:vendor_file:s0\n' > /data/local/tmp/fc
cd /mnt/x; find . -mindepth 1 | while read f; do
  c=$(stat -c '%C' "$f"); echo "/odm/${f#./} $c" >> /data/local/tmp/fc
done; cd /
# 4) 重新打包（--mount-point 必须是 /odm 或 /product 或 /vendor）
mkfs.erofs -zlz4hc,level=9 --mount-point=/odm --file-contexts=/data/local/tmp/fc \
  -T 0 /data/local/tmp/tree.img /data/local/tmp/tree
```
要点：
- **根目录标签必须显式加规则**（如 `/odm u:object_r:vendor_file:s0`），否则 apexd 会因 /odm 根 unlabeled 而重启。
- `--mount-point` 不设会全盘 unlabeled（这是 v03/v04/v07a 卡 logo 的原因之一）。
- system 用从自身镜像里取出的 `plat_file_contexts`、mount-point 为 `/`（默认）。

### 4.2 super 组装（PC）
```powershell
cd C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port
.\scripts\build_super_v06.ps1 `
  -SystemImage <system.img> -VendorImage <vendor.img> -ProductImage <product.img> -OdmImage <odm.img> `
  -Out G:\OriginOS_Work\04_build\vNN_super.img
```
- MTK lpmake 布局，device-size 9,663,676,416，partition 上限约 9,652,142,080。
- 生成的 super 末尾有 AVB footer 吗？没有（make_super 直接写 lp metadata + 数据），BL 已解锁可启动。

### 4.3 刷入
```powershell
fastboot flash super G:\OriginOS_Work\04_build\vNN_super.img   # ~4 分钟
fastboot -w                                                    # 清 userdata+metadata（会丢 /data，含 KSU 模块）
fastboot reboot
```
- recovery adb 也可用：`adb shell "dd if=/dev/block/by-name/super of=/tmp/x"` 反查；或 `dd` 刷入。
- 大文件推送不稳定 → 用 1.4GB 分段 + 逐段校验大小后再 `cat` 拼接（脚本见 `scripts/`）。

### 4.4 日志抓取
- recovery 内：`/sys/fs/pstore/console-ramoops-0`（上一次启动的内核/init console，环 256KB，会覆盖）
  `/sys/fs/pstore/pmsg-ramoops-0`（MTK pmsg，SELinux/service 消息，可读）
- `/data/tombstones/*`（native crash，含 abort message + 栈）
- `/data/system/dropbox`、`/data/anr`（Java 崩溃/ANR；本次为空）
- 设备端 `dmesg`、`logcat` 仅在 Android 起来且 adb 可用时能拿（当前卡在这）。

---

## 5. 镜像资产清单

### super（均可 `fastboot flash super` 刷入）
| 文件 | 说明 | 结果 |
|---|---|---|
| `G:\OriginOS_Work\04_build\v01_rothko_super.img` | rothko 原厂内容重建（对照） | 可开机 |
| `G:\OriginOS_Work\04_build\v02_super.img` | 早期可用版（vivo system v03 + 原厂 odm/product，**需 KSU 模块 permissive + lib 注入**） | 可开机，adb+基带正常（在模块存在时） |
| `G:\OriginOS_Work\04_build\v12_super.img` | **当前刷入**：system v11（含 lib 补丁、移除 SetupWizard、props）+ odm v06（brand=vivo，标签正确） | 可进桌面；adb/MTP/基带/开发者选项仍坏 |
| `v06/v07x/v08/v10/v11/v13…v18` | 各轮实验版本 | 见第 6 节时间线 |

### 关键分区镜像（`04_build_tmp\`）
- `vivo_system_v11.img`（5,871,874,048 B）：v12 的 system（含 init 补丁 lib、移除 SetupWizard、props）
- `vivo_system_v13/v14/v15`: 带“强制 adbd/TCP 5555” rc 的版本（副作用：settings 崩）
- `vivo_system_v16/v17`: CIL typepermissive 实验（无限重启）
- `vivo_system_v18.img`: su 域 setenforce 实验（settings 崩）
- `rothko_odm_v06.img` / `rothko_odm_v07.img`：odm 重打包（brand=vivo，标签正确，864,403,456 B）
- `vivo_product_v03.img` / `vivo_product_v05.img`：product 重打包（v05 含 Devices overlay，标签正确）
- `rothko_vendor_v17.img`：vendor 重打包 + vendor CIL typepermissive（未成功验证）

### vendor_boot
- `G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img`：**当前刷入**（去 AVB + permissive cmdline）
- `G:\OriginOS_Work\02_base\rothko_vendor_boot_selinux0.img`：实验版（selinux=0，**不可用**，zygote 起不来）
- `02_base\images\rothko_current_vendor_boot_a.img`：原厂

### 原厂/基线
- `02_base\images\rothko_current_super.img`（原厂 super，9,663,676,416 B）
- `02_base\images\rothko_current_{system,vendor,product,odm,...}_a.img`
- `G:\OriginOS_Work\03_port\images\*.img`：vivo PD2339 提取的全部 38 个分区镜像

---

## 6. 时间线（关键节点）

| 版本 | 主要改动 | 结果 |
|---|---|---|
| v01 | rothko super 重打包 | 可开机 |
| v02 | vivo system v03 + vivo product/system_ext + rothko vendor/odm + KSU 模块（permissive + lib 注入） | **可开机，桌面/5G/adb 都正常** |
| v03/v04 | 把 lib 补丁烧入 system、移除 SetupWizard、加 portfix rc、加 ro.vivo props、odm/product 重打包 | 卡 logo（当时误判，实为 OOM + 标签问题） |
| v05/v06 | system 只加 lib 补丁，不改 product/odm；补 zram 前的状态 | v06 可开机到 OOBE |
| v07a/b | + odm brand=vivo（错误标签） | 卡 logo |
| v08 | + odm v05（标签修正但根目录 unlabeled） | bootloop（OOM） |
| v10 | system 加 zram swap 配置 | 可开机到 OOBE，不再 OOM |
| v11 | 移除 SetupWizard、ro.debuggable/ro.adb.secure、odm v05 | apexd 失败无限重启 |
| v12 | odm v06（根目录 vendor_file 修复） | **进桌面 ✓（当前基线）** |
| v13 | system v13：把 vivo 的 init.usb.rc 换成 rothko 的 + product overlay | settings 崩、bug 增多（usb.rc 方向错误） |
| v14/v15 | 修正 persist.sys.usb.config 顺序、强制 adbd/TCP 5555 | 能开机，但 adb 不监听、settings 崩 |
| v16 | plat CIL 全局 typepermissive | 无限重启（CIL 未定义 type 编译失败） |
| v17 | plat/vendor CIL 分别 typepermissive | 无限重启 |
| v18 | init.usb.rc 追加 `exec u:r:su:s0 ... setenforce 0` | settings 崩、adb/基带仍坏 |

---

## 7. 下一轮建议（按优先级）

### P0 — 先拿到 adb/logcat（三个问题的前提）
三条候选路线，建议按顺序试：
1. **确认 su 域 setenforce 是否生效**：在 recovery 里用 `dmesg`/pstore 看 v18 启动日志中
   `exec` 行是否报错（如 `init: cannot execve ... Permission denied`），并确认 vivodebug 策略是否被加载
   （`ro.debuggable` 与 `ro.build.type` 相关）。
2. **正确拆分 CIL 的 permissive**：v17 无限重启时，pstore console 里应有 `SELinux: ...` 编译错误行，
   先抓出来，再修正（很可能是某分区 CIL 引用了其它分区定义的 type；需要把 typepermissive 只写进
   “定义该 type 的那个 CIL 文件”）。
3. **绕开 SELinux**：把 `setenforce 0` 做成 init 二进制 patch（vivo init 强制 enforcing 的分支），
   或在 `/vendor/etc/init/hw/init.mt6989.rc`（vendor 域、已被解析）里用 `exec u:r:su:s0 ...`；
   vendor 分区也需要重建（方法同 odm：harvest 标签 + mount-point=/vendor）。

拿到 adb 后立刻做：
- `logcat -b all -d` 抓基带（`RIL`、`ccci`、`modem`）、`settings` 崩溃堆栈、USB（`UsbDeviceManager`、`vusbd`）
- `getenforce`、`ls -Z /dev/ccci*`、`dumpsys telephony.registry`、`dumpsys usb`

### P1 — 基带
- 若 adb 显示 RIL/modem 域 avc denied → 用 permissive 或针对性 allow 修
- 若 RIL 服务没起来 → 对比 v02（正常时）与现在的 `ps -A | grep -E 'ril|modem'`、`getprop | grep -i radio`

### P2 — USB 调试/MTP
- vivo 框架 USB 栈走 `vusbd` + `sys.usb.configfs`；**不要**替换 vivo 的 init.usb.rc（已验证会搞坏 settings）
- 正确方向：让 vivo 的 USB 框架在 rothko vendor 上工作（可能需要从 vivo vendor 补 `vendor.vivo.hardware.*usb*`
  的 HAL/so 到 vendor 镜像，方法：vendor 重打包 + 标签采集）
- 备选：permissive 后 vivo 自家 USB 服务可能自己就通了（v02 时期 adb 可用即证据）

### P3 — 开发者选项崩溃
- 拿 Settings 的 Java 崩溃栈（logcat `AndroidRuntime` / dropbox）再对症；常见原因：
  缺少 vivo 依赖组件（如 `BBKAccount`/`VivoDaemonService` 某接口）、或权限/SELinux

### P4 — 用户的三项修复收尾
1. vivo 账号：odm `ro.product.odm.brand/manufacturer=vivo` 已生效（v12 里账号页能打开）；登录失败需看网络/账号服务日志
2. 关于手机真实数据：`ro.vivo.internet.name`/`ro.vivo.market.name` 已设为 Redmi K70 Ultra；其余字段按截图核对
3. 原子岛/状态栏高度：用 **product v05**（已含 DevicesOverlay，标签正确），单独回归验证，避免和 usb.rc 改动混在一起

---

## 8. 回滚

```powershell
# 回到当前最佳（v12）
fastboot flash super G:\OriginOS_Work\04_build\v12_super.img
# 回到原厂完全体
fastboot flash super C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\02_base\images\rothko_current_super.img
# 恢复原厂 vendor_boot（如需）
fastboot flash vendor_boot C:\...\02_base\images\rothko_current_vendor_boot_a.img
```
注意：`fastboot -w` 会清 /data（联系人/短信/应用 + KSU 模块数据）；如需保留 /data 不要加 `-w`。

---

## 9. 关键脚本索引（`scripts/`）

- 构建：`build_super_v06.ps1`（super 组装，参数化 system/vendor/product/odm）、
  `build_vivo_system*.sh`、`build_v1x_*.sh`（设备端 system/product/odm/vendor 重打包，含标签采集）
- 分区：`toolchain/make_super.py`（MTK lpmake）、`lpdump.py`、`verify_super.py`、`bootimg.py`
- vendor_boot：`toolchain/patch_vendor_boot.py`（去 AVB + 改 cmdline；`--selinux-permissive`/`--strip-avb`）
- 诊断：`collect_logs.sh`、`collect_crash_diag.sh`、`recovery_capture_v08.sh`、`check_*.sh`
- 工具链注意：PC 的 adb 需要把 `TEMP` 指到工作区目录（默认 `%TEMP%` 有权限问题）；
  大文件走 /data/local/tmp，1.4GB 分段推送 + `cat` 拼接最稳。

---

## 10. 收尾补充（09:12 实测）

**重要**：把 super v12 刷入后 **执行一次 fastboot -w（清 /data）再启动**，用户实测：
- 桌面正常 ✓
- **设置可以正常打开** ✓（之前“设置打不开”是 /data 里残留了 v13–v18 各版不同 system 的 settings/DB 状态，不是镜像 bug）
- 关于手机正常（型号 Redmi K70 Ultra）✓
- OOBE 已跳过，直接进桌面 ✓

因此当前交付状态 = **super v12 + 干净 /data → OriginOS 6 可用桌面**。
仍缺：adb/USB(MTP)、基带、vivo 账号登录、开发者选项（后两项需 adb logcat 才能定位）。
下一轮请先按 P0 解决 adb（permissive 或 vivo USB 栈），再做 P1–P4。

---

## 11. v25/v26 结果（2026-08-12 11:20–11:55，已用 adb 逐项验证）

### v25（system 特性版）
- 关于本机型号：o.vivo.market.name / o.vivo.internet.name = Redmi K70 Ultra（真实值）✅
- 镜像级开机自动化（/system/etc/init/hw/init.usb.rc 里追加 service portfix_boot，seclabel u:r:su:s0，
  boot_completed 时执行 /system/etc/portfix_boot.sh）：
  - 自动开启 USB 调试：实测把 db_enabled/development_settings_enabled 置 0 → 重启 → 自动恢复为 1 ✅
  - 跳过 OOBE：实测把 setup_skipped/device_provisioned/user_setup_complete 置 0 → 重启 → 自动恢复为 1，
    HOME 保持 com.bbk.launcher2/.Launcher ✅
  （两项分别重置、分别重启验证）
- USB 调试：**adb over USB 正常**（sys.usb.config=adb，adbd running，Windows 识别 VID_2717&PID_FF08）✅

### v26（product overlay 版）
- product 镜像用「原 product 标签采集 + --mount-point=/product」重建，加入 rothko 的
  DevicesAndroidOverlay.apk(16,892B) / DevicesOverlay.apk(23,757,406B)，标签 vendor_file，根目录 vendor_file ✅
- cmd overlay list 实测两个 overlay **已启用**：
  [x] com.miui.systemui.overlay.devices.android、[x] com.miui.systemui.devices.overlay ✅
- 设置可正常打开（	opResumedActivity=com.android.settings/.Settings）✅

### 当前已知限制（用户已接受 / 说明）
- **相机不可用**：media.camera 服务未注册（CameraService 未完成启动），vivo 相机栈为 vivo 私有
  （ivocameraserver + vivo 专有 HAL/算法库），移植包无法直接打开 —— 用户明确表示“别搞 vivo 相机了”。
- **MTP 文件传输不可用**：当前为保证 USB 调试采用 adb-only gadget 组合；vivo MTP 需要 vivo 的 usbd
  + endor.usb.ffs.mtp.ready（MTK MTP daemon 未 ready）。要 MTP 需回到 vivo USB 栈（会牺牲当前 adb 方案），
  二者当前需权衡。
- 蓝牙可开启（enabled: true），配对/传输需用户实测。

### 全链路验证（adb，v25/v26 实测输出）
`	ext
getprop sys.boot_completed      -> 1
getenforce                      -> Permissive
getprop ro.vivo.market.name     -> Redmi K70 Ultra
getprop ro.product.odm.brand    -> vivo
settings get global adb_enabled  -> 1
settings get global setup_skipped-> 1
HOME resolve                    -> com.bbk.launcher2/.Launcher
telephony.registry mServiceState-> 中国移动 / NR_SA / RSRP -96 (5G)
sensorservice                   -> 50 h/w sensors, 50 running
bluetooth_manager enable        -> enabled: true
wifi dumpsys                    -> WifiState 1, features ok
display dumpsys                 -> 1220x2712
input devices                   -> focaltech_ts (touch)
audio_flinger                   -> audioserver clients ok
overlay list                    -> Devices overlays [x]
`

## 12. Git 仓库

- GitHub（private）：https://github.com/ikun514/OriginOS-Rothko-Port
- 提交内容：脚本/文档/日志/小 lib 补丁（260+ 文件）；ROM 镜像与大转储已被 .gitignore 排除
- 离线 bundle： 0_tools/originos-port.bundle（7.9MB，可 git clone <bundle> 搬运）
