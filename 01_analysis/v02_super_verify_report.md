# v0.2 super.img 离线验收报告

- 目标文件：`G:\OriginOS_Work\04_build\v02_super.img`
- 大小：**9,663,676,416 B (9.00 GiB)**（= super 物理分区大小）
- sha256：**9C9C41F65E62087F5841D9900D170D6A450D37516B7FF4CFDE8B70ADE11DFA23**
- 生成时间：2026-11-12 01:39:55
- 验收方式：纯离线（`verify_super.py` + `lp_tool.py` + 从 super 抽回分区与输入镜像逐字节比对），未操作手机
- 验收结论：**PASS**（0 errors, 0 warnings）

---

## 1. LP 元数据

| 项 | 值 | 判定 |
|---|---|---|
| 布局 | mtk：geometry@4096 + 副本@8192、metadata@12288、data_base=0 | 与现网 stock 一致 |
| geometry magic/checksum | 0x616c4467，校验通过 | ✅ |
| metadata 版本 | 10.2，header_size=256，tables_size=892 | ✅ |
| header checksum / tables checksum | 均通过 | ✅ |
| header flags | 1 (virtual_ab_device) | 与 stock 一致 |
| metadata slots | 3，metadata_max_size=65536 | 与 stock 一致 |
| block device | name=super，size=9,663,676,416，first_logical_sector=2048，alignment=1,048,576 | ✅ 与文件大小一致 |
| 分区/extent/group 表 | partitions 9×52、extents 9×24、groups 3×48、block_devices 1×64 | ✅ |

## 2. 分区表与边界

| # | 分区 | 大小 (B) | file_start | file_end | fs | attrs |
|---|---|---|---|---|---|---|
| 1 | product_a | 393,981,952 | 1,048,576 | 395,030,528 | erofs | READONLY |
| 2 | vendor_a | 1,644,707,840 | 395,313,152 | 2,040,020,992 | erofs | READONLY |
| 3 | system_ext_a | 411,910,144 | 2,040,528,896 | 2,452,439,040 | erofs | READONLY |
| 4 | odm_a | 881,057,792 | 2,452,619,264 | 3,333,677,056 | erofs | READONLY |
| 5 | system_a | 5,894,299,648 | 3,334,471,680 | 9,228,771,328 | erofs | READONLY |
| 6 | mi_ext_a | 126,640,128 | 9,229,565,952 | 9,356,206,080 | erofs | READONLY |
| 7 | vendor_dlkm_a | 21,970,944 | 9,356,443,648 | 9,378,414,592 | erofs | READONLY |
| 8 | system_dlkm_a | 7,471,104 | 9,378,463,744 | 9,385,934,848 | erofs | READONLY |
| 9 | odm_dlkm_a | 348,160 | 9,386,852,352 | 9,387,200,512 | erofs | READONLY |

- Σ 分区大小 = **9,382,387,712 B (8.74 GiB)**
- data_end = **9,387,200,512 B**，与构建前精确模拟（见 `v02_super_build_review.md`）**逐字节一致**
- data_end 之后物理余量 = 276,475,904 B (263.67 MiB)
- extent 按文件偏移排序**无重叠**、全部**不越界**；9 个分区首 extent 处 erofs magic（`e2e1f5e0`）全部识别
- group：default max=0 used=0；**main_a max=9,653,190,656 used=9,382,387,712**（余 270,802,944 B）；main_b max=9,653,190,656 used=0（v0.2 未写 B 槽分区）

## 3. 分区内容抽回比对（关键验证）

用 `lp_tool.py unpack` 从 v02_super.img 抽回全部 9 个分区，与构建输入镜像逐字节比较：

| 分区 | 抽回 sha256（前 16 位） | 输入镜像 | 结果 |
|---|---|---|---|
| product_a | 2a396f7ae00da199… | `G:\OriginOS_Work\03_port\images\product.img` | ✅ MATCH |
| vendor_a | c055b63aa976255f… | rothko_current_vendor_a.img | ✅ MATCH |
| system_ext_a | f3235ab89fbda718… | `G:\OriginOS_Work\03_port\images\system_ext.img` | ✅ MATCH |
| odm_a | 292c2fa3d7112b61… | rothko_current_odm_a.img | ✅ MATCH |
| system_a | cb4878d4f35b054c… | vivo 精简 system（源文件当前不在 G:\04_build，无法直接比对；见下方 EROFS 自检） | ⚠ 源缺失 |
| mi_ext_a | ec2c78e36c9e8587… | rothko_current_mi_ext_a.img | ✅ MATCH |
| vendor_dlkm_a | 61bc18289645540e… | rothko_current_vendor_dlkm_a.img | ✅ MATCH |
| system_dlkm_a | e5152449dc924a5f… | rothko_current_system_dlkm_a.img | ✅ MATCH |
| odm_dlkm_a | 1e2bcde6ecf02906… | rothko_current_odm_dlkm_a.img | ✅ MATCH |

> 8/8 可对照分区全部 MATCH（system_a 源镜像不在当前目录；其 EROFS 结构自检见下节，且 super 内大小与预算一致）。

## 4. system_a（vivo 精简版）EROFS 自检

| 项 | v0.2 system_a | vivo 原 system.img | 说明 |
|---|---|---|---|
| magic / blocksize | 0xE0F5E1E2 / 4096 | 同 | ✅ |
| feature_compat | 0x7 | 0x7 | sb_csum+mtime+… |
| feature_incompat | 0x1 (zero_padding) | 0x1 | legacy 格式 |
| union / lz4_max_distance | **0xFFFF** | 0xFFFF | **legacy LZ4 压缩已启用**（mkfs -zlz4hc 生效） |
| inode 数 | **18,356** | 19,182 | 精简 826 个 inode（与删 `/system/custom` 等预装一致） |
| blocks | 1,439,038 | 1,900,743 | 1,439,038×4096 = 5,894,299,648 = 分区大小 |
| build_time | 0 | 1,230,768,000 | 构建时固定 T=0 |

结论：**v02 的 system_a 是合法的 legacy-LZ4 压缩 EROFS 镜像**，压缩确实生效（与某些只看 `dump.erofs` 输出"无 compr_algs"的误判不同：legacy 镜像不打印 compr_algs，但 union=lz4_max_distance=0xFFFF 即压缩标记）。

## 5. 与刷机链路的对照

- v0.1（rothko 原内容、同 mtk 布局、9,663,676,416 B）已在真机 recovery 用 `dd` 刷写验证：11.6 s 写完、首尾 sha256 一致、重启后 `sys.boot_completed=1` → **v0.2 刷写通道同等有效**。
- v0.2 内容变化 → 必须搭配 patched vendor_boot（fstab 去 AVB + `androidboot.selinux=permissive`）；vendor_boot 的 AVB 签名失效问题已在 `toolchain_report.md` 11.3 说明，建议按 Lead 步骤先单独验证 vendor_boot 可加载。

## 6. 建议的复验命令（离线，秒级~分钟级）

```powershell
# 结构 + 边界 + fs magic 自检
python scripts\toolchain\verify_super.py --built G:\OriginOS_Work\04_build\v02_super.img --expect-size 9663676416

# LP 元数据明细
python scripts\toolchain\lp_tool.py dump G:\OriginOS_Work\04_build\v02_super.img -v

# 需要时抽回分区比对（写入 G:\OriginOS_Work\04_build\_v02_verify）
python scripts\toolchain\lp_tool.py unpack G:\OriginOS_Work\04_build\v02_super.img -o G:\OriginOS_Work\04_build\_v02_verify
```
