# OriginOS 16 固件/系统镜像搜寻报告 + 提取器与容量预算

> task-1 交付物 · 负责人 rom-hunter · 时间 2026-11-12
> 项目：OriginOS 16 (Android 16) → Redmi K70 Ultra (rothko, mt6989)
> 目标机型：vivo iQOO Neo9 Pro 中国版 **PD2339** (Dimensity 9300 / mt6989)

---

## 0. 结论速览

| # | 结论 | 状态 |
|---|---|---|
| 1 | 用户已自行下载的增量 OTA 包**结构完全可用**：v2 头解析正常，38 个分区、manifest 完整、每个分区都带 `old/new_partition_info` 的 SHA256 | ✅ 已验证 |
| 2 | vivo 使用了**非标准 op type 14 = REPLACE_ZSTD**（zstd 压缩的 REPLACE），标准 AOSP 无此类型；已实测确认并写入提取器 | ✅ 已验证 |
| 3 | 除 `audio_dsp` 外，**所有分区都含差分 op（BROTLI_BSDIFF/SOURCE_COPY）**，没有 A15 基线就无法还原任何 system/vendor/product 镜像 | ✅ 已验证 |
| 4 | 提取器 `scripts/payload_extract.py` 已交付并通过**全链路验证**：`audio_dsp` 重建出的镜像 SHA256 与 payload 内 `new_partition_info.hash` **完全一致** | ✅ 已验证 |
| 5 | 容量硬伤：**9 GiB 的 super 装不下任何"直接搬 vivo system"的方案**。最激进的组合仍超 905 MiB，vivo system 必须从 7.389 GiB 压到 ≤6.506 GiB | ⚠️ 关键约束 |
| 6 | 免费直链：本机网络**访问不到 archive.org / t.me / Google**；onfix 等站确认是付费墙。固件包最终由用户自行获取，本条线索保留但不阻塞 | ⚠️ 环境限制 |

---

## 1. 候选来源清单（按 Lead 要求保留线索，未付费、未下载）

> 说明：Lead 通知用户已自行下载完整包后，本项**停止继续深挖**。下表只记录已核实的事实，供后续备选。
> 验证方式：`curl.exe -s -o NUL -w "%{http_code}" --max-time 12 <url>`（部分站点会对无 UA 的自动请求返回 403，不代表资源不存在）。

| 来源 | URL | 免费性 | HTTP 状态(HEAD/GET root) | 大小 | 完整/增量 | 可信度 |
|---|---|---|---|---|---|---|
| **用户已下载增量包** | 本地 `03_port\images\payload.bin` | 免费 | — | 4,129,513,973 B | **增量** (A15 15.1.16.0 → A16 16.2.13.1) | **高**（已完整解析） |
| onfix 官方固件 | `https://onfix.cn/rom/1055741`<br>`PD2339_A_14.0.16.2.W10.V000L1` | **付费**（302 → 登录/VIP） | 302 | 未知 | 完整卡刷包 | 中（内容真、Android 14） |
| gsmmunna | `https://gsmmunna.com/index.php?a=downloads&b=folder&id=4150` | 免费注册 | 403（Cloudflare 拦自动请求） | 未知 | 声称 Stock Firmware | 中 |
| solution-firmware | `https://solution-firmware.com/index.php?a=downloads&b=folder&id=3988` | 待验证 | 未测（同 CMS 家族） | 未知 | China Firmware PD2339 | 低-中 |
| 东海手机维修论坛 | `https://www.donghairom.com/forum-22-11.html`（iQOO 固件版块） | 论坛积分/注册 | 200（列表页） | 未知 | 多为完整卡刷包 | 中（国内维修圈常用） |
| firmwarefile | `https://firmwarefile.com/` | 部分免费 | 200（站点） | 未知 | 需逐页找 PD2339 | 低-中 |
| **archive.org** | `https://archive.org/advancedsearch.php?q=PD2339&output=json` | 免费 | **000 / connection reset** | — | — | **本机网络不可达**（DNS 可解析 69.162.134.178，TCP 握手中被 RST） |
| Telegram 频道预览 | `https://t.me/s/<channel>` | 免费 | **000 / 超时** | — | — | 本机网络不可达（149.154.167.99:443 100% 丢包） |
| **vivo OTA 下载 CDN** | `https://sysupwrdl.vivo.com.cn/` | 免费（官方） | **403**（主机存活！） | — | 官方全量/增量 | **高**，但需要正确的 filename/path 才会返回 200 |
| vivo 官方固件页 | vivo 官网「自助服务-固件下载」 | 免费 | 需中国 IP / 表单 | — | 完整卡刷包 | 高（若用户已拿到全量包，来源很可能就是这里或其镜像） |

**vivo 官方直链规律（部分掌握）**：`sysupwrdl.vivo.com.cn` DNS 正常（223.247.122.5/6、122.228.192.4）且根路径返回 403，说明是活的下载 CDN。文件名规律已由增量包确认：
```
PD2339_A_<版本>.W10.V000L1-update.zip        # 增量
PD2339_A_<版本>.W10.V000L1-update-full.zip   # 全量（预期 ~8.8 GB）
```
拿到用户实际下载的完整包文件名后，可以反推真实 CDN path（多数就是 `https://sysupwrdl.vivo.com.cn/upgrade/download/<filename>` 形式），届时再用 HEAD 验证大小即可，无需再找第三方。

**替代机型（mt6989 vivo，Android 16 全量包同样有价值）**：

| 机型 | 型号 | SoC | 对本次移植的价值 |
|---|---|---|---|
| iQOO Neo9 Pro（中国） | **PD2339** | D9300 | ★★★★★ 原始移植源，vendor 与 rothko 同为 mt6989 |
| iQOO Neo9S Pro / Neo9S Pro+ | PD2404?（待确认） | D9300/D9300+ | ★★★★ 同代，system 系可交叉参考 |
| vivo X100 | PD2309 | D9300 | ★★★★ 同为 D9300，OriginOS 16 完整包可能更早放出 |
| iQOO 12 | PD2306? | SD8G3（**不是** mt6989） | ★★ 仅 system_ext/app 层参考 |

> 结论：**优先等用户的 PD2339 A16 全量包**。若拿不到，再回头搞 PD2309/X100 的 A16 全量包 —— 但因 vendor 系硬件差异大，只能取 system/product/system_ext 做「半移植」。

---

## 2. 补充 A — OTA 提取器交付 `scripts/payload_extract.py`

### 2.1 能力

| 项 | 实现 |
|---|---|
| 头部 | `CrAU` + u64 version + u64 manifest_size + u32 sig_size；**数据区精确偏移** = `24 + manifest_size + sig_size`（v1 为 `20 + manifest_size`，代码按 version 分支） |
| manifest | 手写 protobuf wire-format 解析器（无 .proto 依赖）；正确识别 `PartitionUpdate` 中 **f6=old_partition_info / f7=new_partition_info**（新版布局，非标量 size），并兼容老版标量布局 |
| 自包含 op | `REPLACE(0)` / `REPLACE_BZ(1)` / `REPLACE_XZ(8)` / **`REPLACE_ZSTD(14, vivo 私有)`** / `ZERO(6)` / `DISCARD(7)` |
| 差分 op | `MOVE(2)` `BSDIFF(3)` `SOURCE_COPY(4)` `SOURCE_BSDIFF(5)` `PUFFDIFF(9)` `BROTLI_BSDIFF(10)` `ZUCCHINI(11)` `LZ4DIFF_BSDIFF(12)` `LZ4DIFF_PUFFDIFF(13)` → 明确标记 **NEEDS_BASELINE** 并跳过，退出码 2 |
| 输出 | 按 dst extents 写入 raw `.img`，按 `new_partition_info.size` 截断，打印 SHA256 |
| 校验 | `--verify`：逐 op 校验 `data_sha256_hash` + 整分区 SHA256 与 `new_partition_info.hash` 比对；自测已证明可 `verified=True` |
| 输入 | 直接吃 `payload.bin` **或** 含 payload.bin 的 `.zip`（自动提取，供用户的 8.8 GB 全量卡刷包直接使用） |
| 并发 | `--jobs N` 按分区并行（多线程，zlib/zstd/brotli 均释放 GIL） |
| 其它 | `--json` 导出 manifest 摘要；`--probe-op N` 逆向识别未知 op 码的编码；`--partial` 输出带空洞的半成品（仅供分析，不可启动） |

### 2.2 实测验证结果（真实 vivo 增量包）

```
$ python scripts\payload_extract.py 03_port\images\payload.bin --json 01_analysis\vivo_payload_full.json
payload : ...\03_port\images\payload.bin (3.85 GiB)
version : 2   manifest: 1410961 B   metadata sig: 267 B   block: 4096   minor: 9
data blob offset: 1411252 (0x1588b4)
dynamic partition metadata: {"snapshot_enabled": false, "vabc_enabled": true, ...}
38 partitions, total final size 11.54 GiB (12393840640 B); fully extractable now: 1/38
```

- **`--probe-op 14` 实证**：`audio_dsp` 的 op14 blob（15,783,052 B）经 **zstd** 解出 15,806,464 B，与 dst extents 完全一致；brotli/xz/bz2 全部失败。且 `data_sha256_hash` 与 blob 匹配 → **op14 = REPLACE_ZSTD 确认**。
- **端到端**：`--partitions audio_dsp --verify` → `status=OK, verified=True`，输出镜像 SHA256 与该分区 `new_partition_info.hash` 一致。
- **差分识别**：37/38 个分区被正确标为 NEEDS_BASELINE（`boot/init_boot/dtbo/vendor_boot/vbmeta*/system/vendor/product/system_ext/odm/...`），符合"这是增量包"的事实。

### 2.3 合成自测 `scripts/selftest_payload.py`（回归用）

内置 payload 生成器，覆盖 `REPLACE / REPLACE_BZ / REPLACE_XZ / REPLACE_ZSTD / ZERO` 与「差分分区必须被跳过」：

```
=== SELFTEST PASS ===
  self-contained extraction + sha256 verify : PASS   (byte-for-byte 36864/36864)
  delta partition detected as NEEDS_BASELINE: PASS
```

> 全量包到手后请**先跑自测**再跑真包：`python scripts\selftest_payload.py`，避免拿 8.8 GB 当试验品。

### 2.4 拿到全量包后的标准动作

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
$py = 'C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$env:PYTHONPATH = 'C:\Users\Administrator\Documents\deepseek-harness\default-workspace\OriginOS_Rothko_Port\00_tools\pylibs'

# 1) 先列分区，确认是 full 而不是 delta（关键判据：extract=yes 的分区数应为 38/38）
& $py scripts\payload_extract.py <全量包.zip>

# 2) 真提取（写 G: 盘，解压后 system+vendor+product 等约 11.5 GiB，加 zip 内 payload 峰值需 ~21 GiB）
& $py scripts\payload_extract.py <全量包.zip> --out G:\vivo_pd2339_a16 --verify --jobs 6
```

**磁盘预算提醒**：全量 zip ~8.8 GB + 内部 payload.bin ~8 GB + 解出镜像 11.5 GiB ≈ **28 GB**；项目目录不要放，走 G: 盘。

---

## 3. 补充 B — vivo 增量包实测结论（对后续还原的意义）

38 个分区最终尺寸合计 **12,393,840,640 B (11.54 GiB)**，payload 本体仅 4.13 GB，绝大部分体积是差分数据。

其中**动态分区（决定移植可行性）**：

| 分区 | 最终大小 | 主要 op 构成 |
|---|---:|---|
| system | 7,934,083,072 B (7.39 GiB) | BROTLI_BSDIFF ×6821, REPLACE_ZSTD ×1565, SOURCE_COPY ×1343, REPLACE ×18, ZERO ×4 |
| vendor | 3,135,754,240 B (2.92 GiB) | SOURCE_COPY ×2660, BROTLI_BSDIFF ×1580, REPLACE_ZSTD ×331, ZERO ×2 |
| product | 393,981,952 B (0.37 GiB) | BROTLI_BSDIFF ×62, REPLACE_ZSTD ×21, SOURCE_COPY ×4, ZERO ×1 |
| system_ext | 411,910,144 B (0.38 GiB) | BROTLI_BSDIFF ×580, SOURCE_COPY ×60, REPLACE_ZSTD ×59, ZERO ×2 |
| odm | 4,780,032 B | BROTLI_BSDIFF ×16, SOURCE_COPY ×15, REPLACE_ZSTD ×2, ZERO ×1 |
| vendor_dlkm | 45,801,472 B | BROTLI_BSDIFF ×587, SOURCE_COPY ×459, ZERO ×1 |
| system_dlkm | 14,913,536 B | BROTLI_BSDIFF ×125, SOURCE_COPY ×50, ZERO ×1 |
| odm_dlkm | 348,160 B | BROTLI_BSDIFF ×2, SOURCE_COPY ×2, ZERO ×1 |

**关键点**：`system` 里有 **18 个 REPLACE（明文）** 和 1565 个 REPLACE_ZSTD —— 这些是自包含的，但只占 system 的很小一部分；主体（6821 个 BSLDIFF）必须有 A15 基线。**没有任何分区能靠现有增量包独立还原**（除 audio_dsp）。

**若最终只能拿到 A15 全量包（备选路线）**：需要给提取器补 `BROTLI_BSDIFF` applier（BSDIFF40 patch + brotli 解压 diff/extra 段，纯 Python 可实现，约 150 行），并用 `old_partition_info.hash` 校验基线正确性 —— manifest 里已带每个分区的旧镜像 SHA256，可以严格验证基线版本是否匹配（15.1.16.0.W10）。这条路线技术上完全可行，只是多一步实现工作。

---

## 4. 补充 C — 分区尺寸预算（**打包的关键硬约束**）

> super 是 dm-linear 容器，**不做压缩**：logical 分区每 1 字节都实占 super 1 字节，预算就是纯加总。
> 生成脚本：`scripts/partition_budget.py`（数字可由 `01_analysis/vivo_payload_full.json` 自动更新）。

### 表 A — vivo PD2339 (OriginOS 16.2.13.1) 动态分区最终大小

| 分区 | 字节 | GiB | GB |
|---|---:|---:|---:|
| system | 7,934,083,072 | 7.389 | 7.93 |
| vendor | 3,135,754,240 | 2.920 | 3.14 |
| product | 393,981,952 | 0.367 | 0.39 |
| system_ext | 411,910,144 | 0.384 | 0.41 |
| odm | 4,780,032 | 0.004 | 0.00 |
| odm_dlkm | 348,160 | 0.000 | 0.00 |
| vendor_dlkm | 45,801,472 | 0.043 | 0.05 |
| system_dlkm | 14,913,536 | 0.014 | 0.01 |
| **合计** | **11,941,572,608** | **11.121** | **11.94** |

### 表 B — rothko (Redmi K70 Ultra) 现有 logical 分区

| 分区 | 字节 | GiB | GB |
|---|---:|---:|---:|
| system | 879,894,528 | 0.819 | 0.88 |
| vendor | 1,644,707,840 | 1.532 | 1.64 |
| product | 4,478,963,712 | 4.171 | 4.48 |
| system_ext | 936,296,448 | 0.872 | 0.94 |
| odm | 881,057,792 | 0.821 | 0.88 |
| odm_dlkm | 348,160 | 0.000 | 0.00 |
| vendor_dlkm | 21,970,944 | 0.020 | 0.02 |
| mi_ext | 126,640,128 | 0.118 | 0.13 |
| **合计** | **8,969,879,552** | **8.354** | **8.97** |

### 容量约束

| 项 | 字节 | GiB |
|---|---:|---:|
| super 物理容量 | 9,663,676,416 | **9.000** |
| rothko 现用 logical 合计 | 8,969,879,552 | 8.354 |
| 预留（lp metadata ×2 + backup geometry + 1 MiB 对齐余量） | 62,914,560 | 0.059 |
| **可用余量** | **630,882,304** | **0.588** |

### 问题 1：只把 system 换成 vivo 的，其余全部保留 rothko

```
8.354 GiB − 0.819 GiB(rothko system) + 7.389 GiB(vivo system) = 14.924 GiB
相对 9 GiB 上限 超出 5.924 GiB
```
净增 6.570 GiB，而可用余量只有 0.588 GiB —— **直接搬 system 绝无可能**。
即便同时丢掉 rothko product（4.171 GiB）：`10.752 GiB`，**仍超 1.752 GiB**。

### 问题 2：三种候选组合

rothko 必留件（硬件绑定）：`vendor + odm + odm_dlkm + vendor_dlkm = 2.373 GiB`

| 组合 | 内容 | 总量 GiB | 相对 9 GiB 余量 | 必须从 vivo system 削掉 |
|---|---|---:|---:|---:|
| **组合 1** 全量移植 | vivo system+product+system_ext ＋ rothko vendor 系 ＋ mi_ext | 10.631 | **−1730 MiB** | **1.689 GiB (22.9%)** |
| **组合 2** 全量移植去 mi_ext | 同上，不带 mi_ext | 10.513 | **−1609 MiB** | **1.571 GiB (21.3%)** |
| **组合 3** 最小移植 | 仅 vivo system ＋ rothko vendor 系，product/system_ext 用 64 MiB 空占位 | 9.825 | **−905 MiB** | **0.883 GiB (12.0%)** |

各组合放得下时 vivo system 的上限：

| 组合 | 非 system 固定部分 | vivo system 上限 | 需削减 |
|---|---:|---:|---:|
| 组合 1 | 3.242 GiB | **5.700 GiB** | 1.689 GiB (22.9%) |
| 组合 2 | 3.124 GiB | **5.818 GiB** | 1.571 GiB (21.3%) |
| 组合 3 | 2.436 GiB | **6.506 GiB** | 0.883 GiB (12.0%) |

### 结论

1. **裸替换必死**（超 5.9 GiB）；三种组合**全部超容**，没有任何一种"原样打包"能进 9 GiB。
2. 唯一**不需要删文件**的技术杠杆：重建 `system.erofs` 时启用 **zstd / lz4hc 压缩 + 去重**。vivo 原厂 system 若是未压缩 erofs 或仅 lz4 低档，换 zstd-19 通常省 15–30%：`7.389 × 0.80 ≈ 5.91 GiB` → **组合 3 直接可行**，组合 2/1 也只差少量定向裁剪。
   - 前提：rothko 内核（6.1.138 GKI）需支持 erofs zstd 压缩。这是**下一步必须实测的项**（挂载测试 / `mount -t erofs -o compress=zstd`）。
3. 若只能靠删减：优先删 vivo `system` 里中国区预装（应用商店/钱包/游戏中心/Jovi/浏览器/蓝心小V 等）与 odex/vdex，通常可腾出 1.5–2.5 GiB，足够组合 3/2。
4. `mi_ext`（0.118 GiB）能否删，取决于 rothko vendor 的 `fstab.qcom` / `init` 是否强制挂载 `/mi_ext` —— **需在 `02_base\images\rothko_current_super.img` 的 vendor 镜像里 grep 确认**（下一步）。
5. `system_dlkm`（0.014 GiB）与 vivo `vendor_dlkm`（0.043 GiB）属于 vivo 内核侧，本次移植用 rothko 自己的 kernel + vendor_dlkm，**不计入预算**（上表组合已排除）。

---

## 5. 下一步（建议给 Lead 的排期）

| 优先级 | 动作 | 负责人建议 |
|---|---|---|
| P0 | 用户全量包到手 → 先 `selftest_payload.py`，再 `payload_extract.py <zip>` **只列分区**确认 38/38 extract=yes，然后 `--out G:\... --verify` | rom-hunter |
| P0 | 确认 rothko super 里 `mi_ext` 是否被 vendor 强制挂载（解 lpunpack 后 grep vendor/etc/{fstab*,init*}） | 底包负责人 |
| P1 | 实测 rothko 内核对 **erofs zstd 压缩**的支持；若不支持则改用 lz4hc | toolchain (task-2) |
| P1 | 拿到 vivo 镜像后实测 system.erofs 的体积/压缩比，回填本预算表（脚本已支持 JSON 覆盖） | rom-hunter |
| P2 | 备选路线：若只有 A15 全量包，实现 `BROTLI_BSDIFF` applier 还原 16.2.13.1 | rom-hunter |
| P2 | 若用户包是 PD2309/X100 的 A16 全量包，按"半移植"评估 vendor 差异 | rom-hunter |

---

## 6. 环境与合规备注

- 本机 **Windows 11 LTSC，PowerShell 5.1**：脚本需 `Set-ExecutionPolicy -Scope Process Bypass -Force`；所有交付脚本均用 Python 运行，不依赖 PowerShell 特性。
- Python 依赖位于 `00_tools\pylibs`（brotli / zstandard / lz4 / protobuf），运行时需 `$env:PYTHONPATH` 指向该目录。
- 本次**未**下载任何第三方固件、**未**注册任何站点、**未**付费、**未**运行任何下载的可执行文件；全部结论来自对已提供载荷的解析与 HTTP 探测。
- 网络限制实测：`archive.org`（TCP reset）、`t.me` / `www.google.com`（超时）在本机不可达；`github.com` / `api.github.com` / `firmwarefile.com` / `pan.baidu.com` 可达；`sysupwrdl.vivo.com.cn` 可达（403）。
