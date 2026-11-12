# v0.2 super 构建器复核报告（B）

- 复核对象：`scripts\build_super_v02.ps1`（Lead 编写）+ v0.2 布局预算
- 复核结论：**布局（9 分区顺序、group、device size）正确，按实测尺寸可安全构建**；发现 5 处需要加固/修正的点，已提供加固版 `scripts\toolchain\build_super_v02_checked.ps1`（纯离线、不碰设备）。
- 本文所有数字均为**实测/精确模拟**（sparse 占位文件 + `make_super.py --metadata-only`），不是估算。

---

## 1. v0.2 布局与实测预算（system 精简后 = 5,894,299,648 B）

| # | 分区 | 镜像 | 大小 (B) | super 内 start | super 内 end |
|---|---|---|---|---|---|
| 1 | product_a | vivo product.img | 393,981,952 | 1,048,576 | 395,030,528 |
| 2 | vendor_a | rothko vendor_a | 1,644,707,840 | 395,313,152 | 2,040,020,992 |
| 3 | system_ext_a | vivo system_ext.img | 411,910,144 | 2,040,528,896 | 2,452,439,040 |
| 4 | odm_a | rothko odm_a | 881,057,792 | 2,452,619,264 | 3,333,677,056 |
| 5 | system_a | vivo system 精简版 | 5,894,299,648 | 3,334,471,680 | 9,228,771,328 |
| 6 | mi_ext_a | rothko mi_ext_a | 126,640,128 | 9,229,565,952 | 9,356,206,080 |
| 7 | vendor_dlkm_a | rothko vendor_dlkm_a | 21,970,944 | 9,356,443,648 | 9,378,414,592 |
| 8 | system_dlkm_a | rothko system_dlkm_a | 7,471,104 | 9,378,463,744 | 9,385,934,848 |
| 9 | odm_dlkm_a | rothko odm_dlkm_a | 348,160 | 9,386,852,352 | 9,387,200,512 |

| 指标 | 数值 | 说明 |
|---|---|---|
| Σ 分区大小 | **9,382,387,712 B (8.74 GiB)** | 与 Lead 估算一致 |
| data_end（含逐分区 1MiB 对齐填充） | **9,387,200,512 B (8.74 GiB)** | 真正占用 super 的字节数 |
| 对齐填充总量 | 3,764,224 B (3.59 MiB) | 9 个分区各自向上对齐 1MiB 的累计 |
| device_size | 9,663,676,416 B | super 物理大小 |
| **data_end 之后剩余** | **276,475,904 B (263.67 MiB)** | 物理余量（最大可用冗余） |
| group main_a max（Lead/本复核采用） | 9,652,142,080 B | 与 Lead 一致 |
| Σ vs group max 余量 | **269,754,368 B (257.26 MiB)** | 元数据层面合规 |
| data_end vs group max 余量 | 264,941,568 B (252.67 MiB) | 最保守口径 |
| 备注 | 现网 stock super 的 `main_a` max = 9,653,190,656 B（比 Lead 采用值大 1 MiB） | 两者都 ≥ data_end，均可用 |

> 结论：**预算 PASS**，不存在超限风险；即使 system 精简后再涨 ~250 MiB 也放得下。

---

## 2. 对 `scripts\build_super_v02.ps1` 的复核意见（按严重度）

| # | 问题 | 影响 | 建议 |
|---|---|---|---|
| 1 | 预算用 `$pad = 1048576*9` 粗略估算 | 偏保守（估算 9,437,184 vs 实际 3,764,224），当前不会误判；但数字不精确、无法发现"实际 data_end 超 device"的情况（例如 system 再大 250MB 时估算会先报错，实际仍可能放得下，反之亦然） | 用 exact 1MiB-align 模拟（加固版已实现），同时校验 `data_end ≤ device_size` 与 `Σ ≤ group max` |
| 2 | `$limit=9652142080` 与 `--group main_a:9653190656` 不一致（差 1 MiB） | 元数据里写的 group max 比预算检查值大；不是错误但口径不统一，后续核对易混淆 | 两者使用同一个值（加固版默认统一为 9,652,142,080） |
| 3 | 调用 python 后**未检查 `$LASTEXITCODE`**（`$ErrorActionPreference='Stop'` 不会因 native 程序非零退出而抛错） | make_super 失败时脚本会继续"校验"，把 0 字节/旧文件当成产物打印 sha256。当前 `G:\OriginOS_Work\04_build\v02_super.img` 为 **0 字节**，正是这种风险的实际迹象 | 检查退出码 + 校验输出大小 == 9,663,676,416（加固版已实现） |
| 4 | 校验只用 `scripts\lpdump.py`，且其 **block_devices 解析与本机 64 字节表项布局不匹配** | 见第 3 节：会打印 `name='r'`、`size=7309471332004003842` 等错误字段（在 stock super 上已复现）；分区/group/extent 解析是正确的 | 用 `verify_super.py`（校验三个 LP checksum + 边界 + 不重叠 + fs magic），再把 `lpdump.py` 当辅助 |
| 5 | v0.2 只写 9 个分区（无 `*_b` 空分区） | mmc 直接 dd 刷写没问题；但若未来要用 fastboot/update_engine/快照，B 槽元数据缺失 | 默认保持 9 分区（省空间、符合 v0.2 目标）；如需结构完全对齐现网，加固版提供 `-IncludeEmptyBSlots` |

另：脚本没有校验每个输入镜像是否真的是 EROFS（例如把 product.img 误放成 system_ext 也能构建成功）。加固版的 `verify_super.py` 会在构建后检查每个分区首 extent 的 erofs magic。

---

## 3. `scripts\lpdump.py` block device 解析 bug（实测证据）

同一份 stock super：
```text
# Lead 的 lpdump.py
block devices:
  r                    size=7309471332004003842 first_logical_sector=2048 alignment=1048576

# 我们的 lp_tool.py（已与真机 lpdump -s /dev/block/by-name/super 交叉验证一致）
[block devices]
  [0] name=super  size=9663676416 (9.00 GiB) first_logical_sector=2048 alignment=1048576 entry_size=64
```
原因：本机 LP 10.2 的 block device 表项是 64 字节布局 `u64 first_logical_sector | u64 alignment | u64 size | char name[36] | u32 flags`（无 `alignment_offset`）。`lpdump.py` 按 `u32 alignment_offset@16 / u64 size@20 / name@28` 解析，字段全部错位。
修复片段（若想保留该工具）：
```python
if es == 64:
    fls = r64(e, 0); align = r64(e, 8); size = r64(e, 16)
    name = cstr(e, 24, 36); flags = r32(e, 60)
else:  # 68/72 字节的 AOSP 变体
    ...
```
（我们的 `lp_tool.py` 两种布局都会自动识别，且与真机 `lpdump` 输出逐项一致。）

---

## 4. 加固版构建器用法

```powershell
# 预算自检（不写 9GB，秒级）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\toolchain\build_super_v02_checked.ps1 `
  -VivoSystem G:\OriginOS_Work\04_build\vivo_system_v03.img -DryRun

# 正式构建 + 自检（写 G:\OriginOS_Work\04_build\v02_super.img）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\toolchain\build_super_v02_checked.ps1 `
  -VivoSystem G:\OriginOS_Work\04_build\vivo_system_v03.img -Overwrite
```
脚本行为：
1. 检查 9 个输入存在，打印大小；
2. exact 布局模拟（与 make_super 相同算法），打印每个分区 start/end、Σ、data_end、双重余量；超限即抛错；
3. 写 `01_analysis\v02_super_manifest.json`（布局清单）；
4. 调用 `make_super.py --layout mtk --device-size 9663676416 --group main_a:<统一值>`，**检查退出码**；
5. 校验输出大小 == 9,663,676,416；
6. 用 `verify_super.py` 自检（LP 三个 checksum / data_end 越界 / extent 不重叠 / 每分区 erofs magic / group 未超限）；
7. 若存在 `scripts\lpdump.py`，追加交叉解析（仅作辅助）；
8. 打印最终 sha256 与日志路径 `06_logs\build_super_v02.log`。

---

## 5. 构建后验收清单（建议贴到刷机前检查）

| # | 检查 | 期望 |
|---|---|---|
| 1 | 文件大小 | 9,663,676,416 B |
| 2 | `verify_super.py` 结果 | `PASS (0 errors)`，9 个分区 fs=erofs |
| 3 | data_end | 9,387,200,512（与本报告一致；若 system 尺寸变了会相应变化） |
| 4 | group main_a 已用（Σ） | 9,382,387,712 ≤ 9,652,142,080 |
| 5 | 分区顺序 | product/vendor/system_ext/odm/system/mi_ext/vendor_dlkm/system_dlkm/odm_dlkm |
| 6 | geometry/metadata 位置 | geometry@4096 + 副本@8192、metadata@12288（mtk 布局，与现网一致） |
| 7 | 与 v01 经验对照 | v01 同布局镜像在 recovery `dd` 11.6s、首尾 sha256 一致、可正常启动 → v02 刷写通道已验证可用 |
| 8 | AVB | v02 内容全部改变，必须配合 patched vendor_boot（fstab 去 avb + permissive）使用；`vendor_boot` 的 AVB vbmeta 已保留但签名失效，BL 已解锁（verifiedbootstate=orange），按你步骤③先单独验证 vendor_boot 可加载 |

---

## 6. 风险与备注

1. **v0.2 只有 9 个分区**：直接 `dd` 刷 super 没问题；但 metadata 里没有 `*_b`，如果后续要回滚到原厂 super，直接刷 stock super 即可（回滚包已备好）。
2. **AVB**：v02 的 vendor/system/system_ext 是 vivo/新内容，dm-verity 校验必须靠 patched vendor_boot 去掉 `avb` flag；同时 bootloader 对 vendor_boot 自身的 AVB 校验在 BL 解锁（orange）状态下的行为需实测（你步骤③）。若卡在 bootloader，可在 recovery 用 `flash_part.sh` 回刷原厂 vendor_boot。
3. **system 尺寸变动**：本报告的 data_end 基于 5,894,299,648；若最终镜像大小变化，加固版会重新计算并在超限时直接失败，不会静默产出坏 super。
4. **lpdump.py 仅作辅助**：不要用它打印的 block device 字段做判断（见第 3 节 bug）。
