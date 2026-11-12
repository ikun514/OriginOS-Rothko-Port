# 镜像处理工具链报告（task-2）

- 设备：Redmi K70 Ultra `rothko`，Android 16（BP2A.250605.031.A3），kernel `6.1.138-android14-11`，KernelSU root，SELinux **Enforcing**，page size 4096
- 主机：Windows 11 LTSC，无管理员，未启用 WSL/Hyper-V，无 git/7z/python(PATH)
- 所有操作**未刷机、未重启手机/主机、未写任何真实分区**（super 只做只读 `dd`/`lpdump`）
- 证据目录：`06_logs/`（`toolchain_evidence.log`、`toolchain_erofs_roundtrip.log`、`toolchain_compression_analysis.log`、`toolchain_lpdump_validation.log`）

---

## 0. TL;DR

| 能力 | 状态 | 方案 |
|---|---|---|
| lpunpack（解析/提取 super） | ✅ 完成 | 纯 Python `lp_tool.py`，与真机 `lpdump` 交叉验证一致 |
| lpmake（重建 super） | ✅ 完成 | 纯 Python `make_super.py`，**元数据字节级一致**、分区 sha256 全一致、真机 `lpdump` 通过 |
| EROFS 打包 | ✅ 完成 | 手机 `/system/bin/mkfs.erofs` 1.8.3（lz4/lz4hc/deflate） |
| EXT4 打包 | ✅ 完成 | 手机 `/system/bin/mke2fs` 1.46.6 + `e2fsdroid -e`（SELinux 标签已验证） |
| 手机端 loop 挂载校验 | ✅ 完成 | `losetup -f` + `chcon u:object_r:system_file:s0`（Enforcing 下可挂载） |
| 目录→erofs→挂载→内容校验往返 | ✅ 完成 | 18 个文件 sha256 全 MATCH，镜像已取回 PC |
| zstd EROFS 压缩 | ❌ **不可行（双向）** | mkfs 无 zstd 压缩器；内核无 zstd 解压支持 |
| QEMU TCG 兜底 | 未使用 | 手机自带工具链已完全覆盖需求 |

**对移植容量方案最关键的三条结论**：
1. 现网 super 里 9 个 EROFS 分区**全部是 legacy LZ4 压缩**（`feature_incompat=0x1`，union 字段 `lz4_max_distance=0xFFFF`），分区占用约 98%（8.36 GiB 中用了 8.20 GiB）。
2. **zstd 路线不可行**：`mkfs.erofs` 只注册 lz4/lz4hc/deflate；内核 `CONFIG_EROFS_FS_ZIP=y` 但 `EROFS_FS_ZIP_LZMA not set`，kallsyms 里只有 `z_erofs_lz4_decompress`，deflate 镜像挂载时报 `z_erofs_parse_cfgs: unidentified algorithms 4`。
3. 实测可用的替代压缩收益：**lz4hc,level=9（cluster 16K）比现网 lz4 小 7.6%（odm_a）/ 8.6%（system_a）**；另外本机 GKI 内核**支持 fragments/dedupe 特性**（挂载成功，dmesg 提示 dedupe 为 experimental），可再叠加。

---

## 1. 可用工具清单（手机 `/system/bin`，真实版本）

```text
mkfs.erofs   mkfs.erofs (erofs-utils) 1.8.3     available compressors: lz4, lz4hc, deflate
mke2fs       mke2fs 1.46.6 (1-Feb-2023)         Using EXT2FS Library version android-t-qpr1-beta-2-gpl-369
e2fsdroid    无 --version，支持 -B/-D/-T/-C/-S/-p/-a/-d/-f/-e/-s/-u/-g
dump.erofs   dump.erofs (erofs-utils) 1.8.3
fsck.erofs   fsck.erofs (erofs-utils) 1.8.3     --extract[=X]、-p（打印总压缩率）、--xattrs
lpdump       lpdump (liblp)                     -s 摘要 / 全量分区表
tune2fs / fsck.erofs / losetup(toybox) / mount(toybox)
SELinux 策略文件（打包要用）:
  /system/etc/selinux/plat_file_contexts   /vendor/etc/selinux/vendor_file_contexts
  /system/etc/selinux/plat_property_contexts  /odm /product /system_ext 下同名文件
```

调用方式统一为：`adb shell su -c '...'`（KSU 域 `u:r:ksu:s0`，Enforcing）。

---

## 2. 方案选型与失败记录（按优先级实测）

### 2.1 Termux deb（任务原首选）→ ❌ 放弃，仓库里没有 erofs-utils
- 拉取 `https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz`：HTTP 200，1884844 B，3026 个包。
- 解析依赖闭包：`e2fsprogs` 可完整解析（13 个 deb），但 **`erofs-utils` 不存在**（stanza 检索无匹配）。
- 结论：Termux 只能补 `mke2fs`，无法提供 `mkfs.erofs`。脚本保留：`fetch_termux_tools.py`（可复用下 e2fsprogs）。

### 2.2 vendor_boot 里解出的 Android 原生工具（Lead 建议）→ ❌ 在 Android 用户空间 segfault
- 工具：`02_base/extracted/rothko_vendor_ramdisk/system/bin/{mkfs.erofs,mke2fs,e2fsdroid,dump.erofs,fsck.erofs}`，库 68 个推送到 `/data/local/tmp/tools/lib64`。
- ELF 分析：全部 `PT_INTERP=/system/bin/linker64`，`mkfs.erofs` 只 DT_NEEDED `libc++.so/libc.so/libm.so/libdl.so`（压缩器静态链接，二进制里**没有 zstd 字符串**）。
- 实测（`LD_LIBRARY_PATH=/data/local/tmp/tools/lib64 .../mkfs.erofs --version`）：**Segmentation fault，rc=139**。原因是设备 `/system/bin/linker64` 会优先绑定系统 libc，与 ramdisk 内二进制 ABI 不匹配。
- 结论：这套工具只能在 **recovery/ramdisk 自身环境**里跑（需要重启进 OrangeFox，本次按约束未做）。Android 用户空间请用 `/system/bin` 自带版本。

### 2.3 Alpine aarch64（musl）→ ⚠️ 可跑但同样没有 zstd
- `dl-cdn.alpinelinux.org` v3.21 community / edge 均下载成功：`erofs-utils` 1.8.2-r0 / 1.9.4-r1。
- ELF 依赖：`libuuid.so.1, liblz4.so.1, libz.so.1, libc.musl-aarch64.so.1` —— **无 libzstd/liblzma**，即与手机自带版本能力等价（lz4/lz4hc/deflate），不值得多推 15 MB。
- 产物保留：`00_tools/alpine/`，脚本 `fetch_alpine_tools.py`（若以后需要 musl 版工具可直接复用）。

### 2.4 手机自带 `/system/bin` → ✅ 采用
零下载、版本匹配、与内核 ABI 一致。

### 2.5 QEMU TCG → 未使用（不需要）

---

## 3. 手机端 loop 挂载：SELinux 根因与解法（最容易踩的坑）

**现象**：`losetup` 成功后 `mount -t erofs /dev/block/loopN /mnt` 稳定返回 `I/O error`（EIO），与 erofs 镜像本身无关（`fsck.erofs`/`dump.erofs` 都正常）。

**根因**（dmesg 实锤）：
```text
avc: denied { read } for comm="kworker/u16:0" path="/data/local/tmp/lab/a.erofs"
     scontext=u:r:kernel:s0 tcontext=u:object_r:shell_data_file:s0 tclass=file permissive=0
erofs: (device loop44): erofs_read_superblock: cannot read erofs superblock
```
loop 内核线程（`u:r:kernel:s0`）读不了 `/data/local/tmp` 下 `shell_data_file` 标签的镜像文件 → 内核读超级块失败 → mount 报 EIO。

**解法（无需 `setenforce 0`）**：给镜像文件换一个 kernel 域有 read 权限的标签，挂载后恢复。
```sh
chcon u:object_r:system_file:s0 /data/local/tmp/lab/x.erofs   # 实测 system_file/vendor_file/apex_data_file/system_lib_file 均可
mount -t erofs -o ro /dev/block/loop44 /data/local/tmp/lab/mnt
# ... 校验 ...
umount /data/local/tmp/lab/mnt
chcon u:object_r:shell_data_file:s0 /data/local/tmp/lab/x.erofs
```
交叉验证：`setenforce 0` 后同一条 mount 也能成功（随后立即 `setenforce 1`），证明是 SELinux 而非 erofs/loop 问题。

**loop 设备分配的第二个坑**：本机 loop 节点 minor = `index*8`（如 loop44 = 7:352），手工 `mknod /dev/block/loop44 b 7 44` 会得到 `Bad file descriptor`；且 `loop0..45` 已被 APEX 大量占用。正确做法：
```sh
L=$(losetup -f)          # toybox 会按需通过 loop-control 创建新设备（如 /dev/block/loop44）
losetup "$L" img && mount -t erofs -o ro "$L" mnt
losetup -d "$L"
```
封装在 `scripts/toolchain/dev_lib.sh`（`find_free_loop/attach_loop/mount_image/unmount_image/tree_sha256`）。

---

## 4. EROFS 打包 + 完整往返验证 ✅

### 4.1 打包命令
```sh
su -c 'mkfs.erofs -d2 -T 1700000000 --mount-point=/system \
  --file-contexts=/system/etc/selinux/plat_file_contexts \
  -L system -zlz4hc,level=9 -C16384  /data/local/tmp/lab/tree.erofs /data/local/tmp/lab/roundtrip/src'
```
真实输出（节选）：
```text
Build completed.
Filesystem total blocks: 99 (of 4096-byte blocks)
Filesystem total inodes: 32
```
`dump.erofs -s`：
```text
Filesystem magic number: 0xE0F5E1E2
Filesystem blocksize: 4096
Filesystem blocks: 99
Filesystem compr_algs: lz4
Filesystem features: sb_csum mtime xattr_filter 0padding compr_cfgs big_pcluster
```

### 4.2 目录 → erofs → 挂载 → 内容校验（PC 编排：`scripts/toolchain/roundtrip.ps1`）
流程：PC 构造 18 文件目录树（含子目录、262144B 随机 apk、131072B 随机 apk、带空格文件名、中文文件名、空文件、init.rc、可执行脚本）→ `tar.gz` → push → 手机解包 → `mkfs.erofs` → `losetup -f`+`chcon`+`mount -t erofs` → 逐文件 sha256 → 卸载 → 报告 + 镜像取回 PC → PC 端再校验 erofs magic。

真实结果：
```text
src_entries: 18
image: /data/local/tmp/lab/roundtrip/tree.erofs
image_size: 405504
mount_fstype: erofs
checksums_match: YES
挂载目录 SELinux 标签: u:object_r:system_file:s0  (bin/etc/usr/... 全部为 system_file)
PC 取回: 04_build/lab/from_device/tree.erofs  405,504 B  sha256=88738057a21be2f27ff6a0d22c5484970da8c5f545d3eee6ea8dd28a002c93ae
erofs_magic@1024 = e2e1f5e0  → ok
local files: 18, device-report files: 18, only-local: 0
```
日志：`06_logs/toolchain_erofs_roundtrip.log`，报告：`04_build/lab/from_device/roundtrip_report.txt`。

### 4.3 EROFS 特性/压缩器与内核兼容矩阵（全部实测）

| 能力 | mkfs.erofs 1.8.3 | 内核 6.1.138 GKI | 挂载实测 |
|---|---|---|---|
| lz4 / lz4hc | ✅ | ✅ (`CONFIG_EROFS_FS_ZIP=y`, `z_erofs_lz4_decompress`) | ✅ |
| zstd | ❌ `Cannot find a valid compressor zstd` | ❌ 无相关符号 | — |
| lzma | ❌ `Cannot find a valid compressor lzma` | ❌ `# CONFIG_EROFS_FS_ZIP_LZMA is not set` | — |
| deflate | ✅（EXPERIMENTAL 警告） | ❌ `z_erofs_parse_cfgs: unidentified algorithms 4` | ❌ |
| `-Efragments` / `-Ededupe`（配 lz4hc） | ✅ | ✅ 可挂载（dedupe 有 `EXPERIMENTAL global deduplication` 提示） | ✅ |

> 结论：**容量优化的唯一可用压缩算法是 lz4/lz4hc**；fragments/dedupe 可叠加使用。

---

## 5. EXT4 打包 ✅（含 e2fsdroid 踩坑）

### 5.1 正确流程（AOSP 同款）
```sh
# 1) 从目录建 ext4 并复制文件（uid/gid/mode/symlink 全保留）
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -d <src_dir> -O ^has_journal -L system <img> <blocks>
# 2) 只写 SELinux xattr（-e = 已有文件系统模式）
e2fsdroid -e -S /system/etc/selinux/plat_file_contexts -a /system <img>
```
真实结果：
```text
e2fsdroid rc=0
Created filesystem with 18/16384 inodes and 1070/16384 blocks
tune2fs: volume name=system, Block count=16384, Block size=4096, Inode size=256
mount -t ext4 -o ro /dev/block/loop45 /mnt  → 成功
ls -Z: u:object_r:system_file:s0  (bin/hello.txt/sub/lost+found 全部带标签)
sha256 校验: CHECKSUMS_MATCH（含符号链接 bin/sh -> /system/bin/sh）
```
镜像：`/data/local/tmp/lab/ext4/system_ext4.img`（64 MiB，脚本 `pack_ext4.sh` + `ext4_test.sh`）。

### 5.2 失败记录（供后续排查）
| 现象 | 原因 | 处理 |
|---|---|---|
| `e2fsdroid: Invalid argument while opening file (img)` | 传了 `-f src_dir`（"从零建文件"模式）与已 `mke2fs -d` 填充的文件系统冲突 | 去掉 `-f`，改用 `-e` |
| `ext2fs_mkdir: Ext2 directory already exists while making dir "bin"` + rc=1 | 同上（`-e` 与 `-f` 同时给） | 只用 `-e` |
| `fsck.erofs --extract --xattrs` 报 `failed to set xattr security.selinux ... Operation not supported` | ksu 域无 CAP_MAC_ADMIN，无法往 /data 写 security.selinux xattr | 不要用 xattr 解包/恢复路线；标签走 `--file-contexts`(erofs) / `e2fsdroid -e`(ext4) |

---

## 6. super / liblp 工具（纯 Python）

### 6.1 现网 super 镜像的**非标准布局**（重要）
`02_base/images/rothko_current_super.img` = 9,663,676,416 B（9.00 GiB），与 live 分区 `/dev/block/by-name/super` 前 64 KiB **逐字节一致**，真机 `lpdump -s` 解析正常。布局特殊：

```text
[0, 4096)        全 0
[4096, 8192)     LpMetadataGeometry（struct 52，checksum 正确）
[8192, 12288)    Geometry 副本（与上一份完全相同）
[12288, ...)     Metadata slot 0；slot stride = metadata_max_size = 65536，共 3 个 slot
[1 MiB, ...)     分区数据（extent target_data 以 super 起点为 0 的 512B 绝对扇区）
```
标准 AOSP 布局是 geometry@0 / metadata@4096，因此解析器必须**自动探测布局**（`lp_tool.find_layout`：扫 geometry magic → 校验 checksum → 在 +4096/+8192 找可校验的 metadata → 用分区首 extent 处的 erofs magic 给数据 base 打分）。

### 6.2 `lp_tool.py dump` 结果（已存 `01_analysis/rothko_super_lp.json`）
```text
container=raw file_size=9663676416 (9.00 GiB) slot=0
layout: geometry@4096 metadata@12288 data_base@0 (非标准布局)
geometry: struct=52 checksum_ok=True metadata_max_size=65536 slot_count=3 logical_block_size=4096
metadata: v10.2 header_size=256 header_checksum_ok=True tables_size=1360 tables_checksum_ok=True
          flags=1 (virtual_ab_device)
          tables: partitions(18×52) extents(9×24) groups(3×48) block_devices(1×64)
block device: name=super size=9663676416 first_logical_sector=2048 alignment=1048576 entry_size=64
groups: default(0)  main_a(9653190656 = 8.99 GiB)  main_b(9653190656)
```
| 分区 | 大小 | group | extents | 文件系统 |
|---|---|---|---|---|
| odm_a | 881,057,792 (840.24 MiB) | main_a | 1 (2048+1720816) | erofs |
| odm_b | 0 | main_b | — | — |
| odm_dlkm_a | 348,160 | main_a | 1 (1724416+680) | erofs |
| product_a | 4,478,963,712 (4.17 GiB) | main_a | 1 (1726464+8747976) | erofs |
| system_a | 879,894,528 (839.13 MiB) | main_a | 1 (10475520+1718544) | erofs |
| system_dlkm_a | 7,471,104 | main_a | 1 (12195840+14592) | erofs |
| system_ext_a | 936,296,448 (892.92 MiB) | main_a | 1 (12212224+1828704) | erofs |
| vendor_a | 1,644,707,840 (1.53 GiB) | main_a | 1 (14041088+3212320) | erofs |
| vendor_dlkm_a | 21,970,944 | main_a | 1 (17254400+42912) | erofs |
| mi_ext_a | 126,640,128 | main_a | 1 (17297408+247344) | erofs |
| 其余 *_b | 0 | main_b | — | — |

- 9 个非空分区合计 **8,977,350,656 B (8.36 GiB)**；`partition_data_within_file = True`。
- 9 个分区首个 extent 处 magic 全部为 `e2e1f5e0`（EROFS）→ 数据 base=0 判定正确（打分 9/9）。
- 与 live 分区 `lpdump -s /dev/block/by-name/super` 的分区名/group/extent(target_data) 完全一致。

### 6.3 `lp_tool.py unpack` 结果（全分区已抽取到 `G:\OriginOS_Work\02_base\lp_parts\`）
```text
[ok] odm_a          881057792   sha256=292c2fa3d7112b61...  fs=erofs
[ok] odm_dlkm_a        348160   sha256=1e2bcde6ecf02906...
[ok] product_a      4478963712  sha256=e973762916fefaa6...
[ok] system_a        879894528  sha256=bcc43f2c9da53b39...
[ok] system_dlkm_a     7471104  sha256=e5152449dc924a5f...
[ok] system_ext_a    936296448  sha256=73d7bc75b217987d...
[ok] vendor_a       1644707840  sha256=c055b63aa976255f...
[ok] vendor_dlkm_a    21970944  sha256=61bc18289645540e...
[ok] mi_ext_a        126640128  sha256=ec2c78e36c9e8587...
（summary 写入 PARTITIONS.sha256 / unpack_manifest.json）
```

### 6.4 `make_super.py`（lpmake）验证——字节级
命令示例（rothko 同布局、全 9 个分区）：
```powershell
python make_super.py -o super_rebuilt.img --device-size 9663676416 --layout mtk `
  --group main_a:9653190656 --group main_b:9653190656 `
  --partition odm_a:main_a:ro:G:\...\odm_a.img --partition odm_b:main_b:ro:- ... (共 18 条)
```
结果：
1. **元数据区（前 208,896 B = 12288 + 3×65536）与原始 super 的 sha256 完全相同**：
   `bc7a52edaf5057b7da6a383d4e895e8359bc4462df0f21b080e5c75ac0b9ec92`（原始 = 重建）
2. 9/9 分区重新抽取后 **sha256 与原始分区逐一 MATCH**。
3. 整文件 sha256 不同（3.35% 字节差异，324,009,984 B），差异范围**全部落在对齐 padding / 未使用尾部**（原始 super 的残留数据，重建时为零），元数据与分区数据区域完全一致 —— 属正常现象。
4. 手机真机 `lpdump -s` 对 **standard 与 mtk 两种布局的生成镜像均 rc=0**，分区名/group/attrs/extents 解析正确：
   ```text
   Slot 0:
   Metadata version: 10.2
   Metadata size: 1616 bytes
   Metadata max size: 65536 bytes
   Metadata slot count: 3
   Header flags: virtual_ab_device
   Partition table:
     Name: odm_a   Group: main_a   Attributes: readonly   Extents: 0 .. 1720815 linear super 2048
     ...
   ```
   产物：`G:\OriginOS_Work\02_base\super_rebuilt_mtk_ro.img`、`super_meta_only.img`、`02_base/extracted/lp_test/super_mini_{standard,mtk}.img`。

> 结论：lpmake 对 rothko 现网布局是**字节级精确**的；真要刷机时 standard 布局也被设备 liblp 接受。

---

## 7. 压缩 / 容量分析（给移植方案的关键数据）

### 7.1 现网 EROFS 分区的压缩状态（`erofs_info.py` 离线解析 superblock，与真机 `dump.erofs -s` 一致）
| 分区 | 分区大小 | erofs 已用 | 占用率 | 压缩 | inodes |
|---|---|---|---|---|---|
| odm_a | 881,057,792 | 864,468,992 | 98.1% | lz4(legacy, max_distance=65535) | 1285 |
| odm_dlkm_a | 348,160 | 45,056 | 12.9% | 同上 | 6 |
| product_a | 4,478,963,712 | 4,395,016,192 | 98.1% | 同上 | 1893 |
| system_a | 879,894,528 | 863,326,208 | 98.1% | 同上 | 4207 |
| system_dlkm_a | 7,471,104 | 7,241,728 | 96.9% | 同上 | 72 |
| system_ext_a | 936,296,448 | 918,683,648 | 98.1% | 同上 | 2493 |
| vendor_a | 1,644,707,840 | 1,613,824,000 | 98.1% | 同上 | 6262 |
| vendor_dlkm_a | 21,970,944 | 21,475,328 | 97.7% | 同上 | 281 |
| mi_ext_a | 126,640,128 | 124,645,376 | 98.4% | 同上 | 143 |
| 合计 | 8,977,350,656 | 8,808,726,528 | 98.1% | | |

（`feature_incompat=0x1` 仅 zero_padding、无 COMPR_CFGS → **legacy LZ4**；union 字段 `lz4_max_distance=0xFFFF`。）

### 7.2 实测：解包 → 重新压缩对比（`comp_analysis.sh`，全部在手机本地完成）
从 live super 只读 `dd` 出分区 → `fsck.erofs --extract` 解出目录 → 用不同参数重打包 → 挂载 + 抽样 sha256 校验：

| 分区 | 解压后未压缩体积 | 文件数 | 原镜像大小 | 重打 lz4hc,level=9,-C16384 | 对比原镜像 | 重打普通 lz4 | 对比 |
|---|---|---|---|---|---|---|---|
| odm_a | 1,272,663,031 B (1.18 GiB) | 1114 | 881,057,792 | **814,264,320** | **0.9242（−7.6%）**，22 s | 893,153,280 | 1.0137 |
| system_a | 1,333,839,501 B (1.24 GiB) | 3524 | 879,894,528 | **804,454,400** | **0.9143（−8.6%）**，10 s | 911,020,032 | 1.0354 |

- 重打包镜像 `mount -t erofs` 全部成功，抽样文件 sha256 与解包目录 **MATCH**（odm: goodix apk / SoterProvisioningTool_mitee / capture.sh；system: init.environ.rc / com.android.adbd.capex / com.android.adservices.capex）。
- 现网压缩比（未压缩/镜像）：odm_a 1.44×、system_a 1.52×；**vivo 用的是普通 lz4，换 lz4hc 可再省 7.6~8.6%**。
- 容量推算：按 8.36 GiB A 侧数据 × ~8% ≈ **可省约 0.64~0.72 GiB**；若叠加 `-Ededupe`/`-Efragments`（内核可挂载）还有额外空间，需用真实目录实测。
- zstd：**双向不可行**（见 4.3），因此"重新用 zstd 压缩省容量"的方案在本机内核上走不通；应改用 lz4hc + dedupe/fragments + 缩小分区 padding 的组合。

---

## 8. 交付脚本与用法（`scripts/toolchain/`）

| 脚本 | 运行位置 | 用途 |
|---|---|---|
| `lp_tool.py` | PC（Python3） | `dump`（打印/导出 lp 元数据 JSON）、`unpack`（提取分区 raw 镜像）；支持 raw/sparse super、自动布局探测 |
| `make_super.py` | PC（Python3） | lpmake：按 group/分区列表重建 super；`--layout standard\|mtk`、`--metadata-only`；校验和全部正确 |
| `erofs_info.py` | PC（Python3） | 离线解析 EROFS superblock（压缩算法/blocks/inodes/特性），`--super` 可对整份 super 出表 |
| `dev_lib.sh` | 手机（source） | loop 分配、chcon 挂载封装、目录 sha256 |
| `pack_erofs.sh` | 手机 | 目录 → erofs（lz4/lz4hc/none、mount-point、file-contexts、label/uuid/timestamp） |
| `pack_ext4.sh` | 手机 | 目录 → ext4（mke2fs -d + e2fsdroid -e 标签） |
| `roundtrip_erofs.sh` | 手机 | 完整往返：解包 tar → 打包 → 挂载 → sha256 → 报告 |
| `ext4_test.sh` / `comp_analysis.sh` / `feat_test*.sh` | 手机 | 回归/分析测试 |
| `dev_caps2.sh` / `device_probe.sh` / `evidence_collect.sh` | 手机 | 能力探测与证据汇总 |
| `device_run.ps1` | PC | 通用"push 脚本 → su 执行 → 拉回产物 + sha256"（自动去 CRLF） |
| `roundtrip.ps1` | PC | 一键跑完整 erofs 往返并取回镜像/报告 |
| `fetch_termux_tools.py` / `fetch_alpine_tools.py` | PC | 备用 deb/apk 下载解包（含依赖闭包解析） |

常用命令：
```powershell
# 解析 super
python scripts\toolchain\lp_tool.py dump 02_base\images\rothko_current_super.img --json 01_analysis\rothko_super_lp.json -v
# 提取分区
python scripts\toolchain\lp_tool.py unpack ...\rothko_current_super.img -o G:\OriginOS_Work\02_base\lp_parts --partitions system_a,vendor_a
# 重建 super
python scripts\toolchain\make_super.py -o super.img --device-size 9GiB --layout mtk --group main_a:9653190656 --partition system_a:main_a:ro:system_a.img ...
# 手机端打包 + 挂载往返
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\toolchain\roundtrip.ps1
# 手机端任意脚本
powershell -File scripts\toolchain\device_run.ps1 -Script scripts\toolchain\ext4_test.sh -ExtraScripts scripts\toolchain\dev_lib.sh,scripts\toolchain\pack_ext4.sh
```

---

## 9. 已知限制与风险

1. **zstd/lzma/deflate 压缩镜像无法在本机内核挂载**；deflate 虽可创建但 `z_erofs_parse_cfgs: unidentified algorithms 4`（内核不支持）。
2. 手机 `/data/local/tmp` 空间有限（本次用约 8 GB 临时数据后已清理）；大批量构建建议用 `/sdcard/work`（460 GB 空闲），并用 tar 传递以避开 f2fs 大小写不敏感问题。
3. KSU 域不能写 `security.selinux` xattr（`fsck.erofs --xattrs` 解包失败）→ 标签必须"打包时写入"（erofs 用 `--file-contexts`，ext4 用 `e2fsdroid -e`），不能"解包后再恢复"。
4. 未做任何刷机/分区写入；`make_super.py` 产物仅通过 `lpdump` 与解析器验证，未上机刷写。
5. 手机 adb 在 01:05 左右曾掉线约 2 分钟（无操作触发），恢复后继续；若再次出现，先 `adb kill-server; adb start-server`，仍无则检查 USB 物理连接。
6. `make_super.py` 目前每个分区只写 1 个 LINEAR extent（v1 最小可用）；小于 1 MiB 的分区会被 1 MiB 对齐撑开（与现网行为一致）。多 extent/稀疏写入未实现。
7. lz4hc 重新压缩的实测样本是 odm_a/system_a；product_a（4.17 GiB）未做完整"解包→重压"（耗时与空间考虑），但方法相同，套用 −7~−9% 估算。

---

## 10. 证据文件索引
| 文件 | 内容 |
|---|---|
| `06_logs/toolchain_evidence.log` | 设备/工具版本、zstd 失败、内核 CONFIG、lpdump 校验、往返报告、ext4 标签、压缩摘要（140 行，脚本 `evidence_collect.sh` 可复现） |
| `06_logs/toolchain_erofs_roundtrip.log` | PC 编排 erofs 往返全过程（18 文件 sha256、pull、校验） |
| `06_logs/toolchain_compression_analysis.log` | 压缩率分析摘要 + `dump.erofs -s` |
| `06_logs/toolchain_lpdump_validation.log` | 设备 `lpdump` 对生成 super 的解析结果 |
| `04_build/lab/from_device/tree.erofs` | 往返产出的 erofs 镜像（405,504 B） |
| `04_build/lab/from_device/roundtrip_report.txt` | 设备端生成的往返报告（含 dump.erofs、源 sha256 列表） |
| `01_analysis/rothko_super_lp.json` | super LP 元数据完整 dump（JSON，含 extents/attrs/checks） |
| `01_analysis/rothko_erofs_compression.json` | 9 个分区 EROFS 压缩/特性统计（JSON） |
| `02_base/extracted/lp_test/super_mini_{standard,mtk}.img` | 64 MiB 测试 super（两种布局，lpdump 已验证） |
| `G:\OriginOS_Work\02_base\super_rebuilt_mtk_ro.img` | 9 GiB 全量重建 super（元数据字节级一致） |
| `G:\OriginOS_Work\02_base\lp_parts\` | 9 个 A 侧分区 raw 镜像 + sha256/JSON |

---

## 11. 追加交付（Lead 追加任务 A/B/C，2026-11-12 01:20+）

### 11.1 重要更正：现网镜像**不是未压缩，而是 legacy LZ4 压缩**
`dump.erofs -s` 对 legacy 格式镜像不打印 `compr_algs`，容易误判为"未压缩"。实际判定依据（`erofs_info.py` 直接解析 superblock）：
- vivo 与 rothko 的 9 个 erofs 镜像全部：`feature_incompat=1 (zero_padding)`、**无 `COMPR_CFGS`**、union 字段 `lz4_max_distance=65535` → 这是 **legacy LZ4 压缩** 的标记。
- 决定性反证（手机 `fsck.erofs --extract` 实测解包体积 > 镜像体积）：
  - rothko `odm_a`：881,057,792 B 镜像 → 解出 **1,272,663,031 B**（1114 文件，≈1.44×）
  - rothko `system_a`：879,894,528 B → **1,333,839,501 B**（3524 文件，≈1.52×）
  - vivo `product.img`：原 393,981,952 B ↔ lz4hc 重打包 386,523,136 B ≈ 其 blocks 386,514,944 B（原本已压缩、且 APK 难压，故几乎无收益）
- 影响：**不能再指望"从未压缩变压缩"来腾容量**；容量方案 = 精简 vivo system + lz4hc + 缩短分区 padding，zstd 路线在本机不可用。

### 11.2 任务 A：rothko 原内容重建 super（v0.1 测试包）
一键脚本：`scripts/toolchain/rebuild_rothko_super.ps1`
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\...\OriginOS_Rothko_Port\scripts\toolchain\rebuild_rothko_super.ps1
```
- 输入：`02_base\images\rothko_current_<name>.img`，缺失则自动用 `lp_tool.py unpack` 从 `rothko_current_super.img` 提取到 `G:\OriginOS_Work\02_base\lp_parts\`
- 参数固化：`--layout mtk --device-size 9663676416 --group main_a:9653190656 --group main_b:9653190656`，18 个分区（9 个 A 侧实体 + 9 个 B 侧空分区，attrs 全部 ro，与现网一致）
- 输出：`G:\OriginOS_Work\02_base\super_v01_rothko_rebuild.img`
- 自检：`scripts/toolchain/verify_super.py --built ... --reference rothko_current_super.img --expect-size 9663676416`
  检查 LP 三个 checksum、block_device size==文件大小、9 个 A 分区大小/顺序与原始一致、extent 互不重叠且不越界、每个首 extent 处 erofs magic 可识别、group 不超限；退出码 0=PASS。
- 已手工验证的等价结论：重建 super 的**元数据区（前 208,896 B）与原始 super sha256 完全相同**（`bc7a52edaf5057b7da6a383d4e895e8359bc4462df0f21b080e5c75ac0b9ec92`），9/9 分区数据 sha256 MATCH；整文件 3.35%（324,009,984 B）差异全部落在对齐 padding/未使用尾部。日志：`06_logs/rebuild_super.log`。
- **最终产物（脚本实跑）**：`G:\OriginOS_Work\02_base\super_v01_rothko_rebuild.img`，9,663,676,416 B，`sha256=065da5affaeadb0aff629f72a8ff176983f955ed4e967a0bf062105812b493fd`，`verify_super.py` 结果 **PASS（0 errors, 0 warnings）**；9 个 A 分区 file_start/file_end 依次为 odm_a 1,048,576→882,106,368 … mi_ext_a 8,856,272,896→8,982,913,024，无重叠、不越界；与参考 super 比对 18/18 分区、3/3 group 一致。

### 11.3 任务 B：`patch_vendor_boot.py`（vendor_boot v4 补丁）
产物：`G:\OriginOS_Work\02_base\rothko_vendor_boot_patched.img`，`sha256=7847b5ccf1720b41dc30ea08b414ce2cee0b6fcbb38acbae0e513c7cf5bf887f`（64 MiB，与原分区同大小）；报告 `01_analysis/vendor_boot_patch_report.json`。
- 输入镜像结构（实测）：header v4 / page 4096 / header_size 2128 / vendor_ramdisk_size 62,417,363 / table 216 B(2×108, 位于 dtb 之后) / dtb 444,690 B（段首有 64 B 非 FDT 前缀，原样保留）/ bootconfig 0 / AVB vbmeta 704 B @62,873,600 / AVB footer @67,108,800。
- 改动 1：`first_stage_ramdisk/fstab.mt6989` 9461→9020 B，删除 **23 个 AVB token**：`avb=vbmeta_system`、`avb_keys=/avb/q-gsi.avbpubkey:…`、裸 `avb`（vendor/product/odm/*_dlkm）、`avb=vbmeta`（mi_ext、vbmeta_system emmc 行）。按 Lead 要求 GSI avb_keys 一并删除（可用 `--force-gsi-avbkeys` 保留）。
- 改动 2：cmdline `bootopt=64S3,32N2,64N2` → `bootopt=64S3,32N2,64N2 androidboot.selinux=permissive`
- 重建：platform fragment 重新 cpio + gzip -9 -n（mtime=0/OS=3/XFL=2），recovery fragment、dtb 段、vbmeta 逐字节保留，fragment 表 size/offset 更新，页对齐正确（image_end 62,873,600 不变）。
- 自检 PASS：reparse 后 fragment 自洽、cpio 756 条目仅 fstab 变化、fstab 内无残留 `avb*`、cmdline 正确。
- ⚠️ AVB vbmeta 保留但签名必然失效（footer 的 original_image_size/vbmeta_offset 已同步更新）；刷机必须关闭 AVB 验证，或使用 `--strip-avb` 输出无 AVB 版本。

### 11.4 任务 C：rothko 侧 lz4hc 重压缩实测（手机端，解包→重打包→挂载抽检）
| 分区 | 原镜像 | 解压后体积(文件数) | lz4hc L9 | lz4hc L12 |
|---|---|---|---|---|
| vendor_a | 1,644,707,840 | 2,555,790,416 (5302) | **1,489,944,576 (−9.41%)**，17 s | 1,487,917,056 (−9.53%)，56 s |
| odm_a | 881,057,792 | 1,272,663,031 (1114) | **814,264,320 (−7.58%)**，39 s | 813,498,368 (−7.67%)，64 s |
| system_a（先前） | 879,894,528 | 1,333,839,501 (3524) | **804,454,400 (−8.57%)**，10 s | — |

结论：用 **level=9** 即可（L12 仅多省 0.1%、耗时约 3 倍）。rothko 侧 8.36 GiB 全量重压预计省 ~0.7 GiB。脚本 `comp_levels.sh`，数据 `/data/local/tmp/lab/comp/summary_levels.txt`。
另：`-zlz4hc -Efragments`/`-Ededupe` 镜像在 6.1 内核**可正常挂载**（dedupe 为 experimental 提示），可叠加用于进一步压缩。

---

## 12. 追加交付 2（Lead 第二轮要求 A/B/C，2026-11-12 01:30+）

### 12.1 A：一键回滚包（stock super + vendor_boot）✅
- 清单：`scripts\toolchain\rollback\stock_manifest.json`
  - `rothko_current_super.img` 9,663,676,416 B `sha256=dc61e94414b3f8c7c998dc787e101437e2105a374dab683d9ca6c3ba9be9bdbd` → `/dev/block/by-name/super`
  - `rothko_current_vendor_boot_a.img` 67,108,864 B `sha256=dd453a760bb6066264fafdf756aceba0ba659f4a1e2ca0673608a9cee255d0d3` → `/dev/block/by-name/vendor_boot_a`（当前 slot _a，支持 `--both-slots`）
- PC 编排：`scripts\toolchain\restore_stock.ps1`
  - `-Mode prepare`（默认，**仅 Android 模式**）：本地 sha256 校验 → `/sdcard 空间检查`（≥10.5G）→ push 到 `/sdcard/work/rollback/` → 设备端 sha256 校验 → 打印 recovery 步骤；已存在且 hash 一致的镜像会跳过重传
  - `-Mode verify`：系统启动后 `su dd | sha256sum` 读回整分区对比 manifest
  - `-Mode stream -ConfirmWrite`：兜底方案，PC stdin 直接 `adb shell dd` 写分区（recovery 场景，无需 staging）
- recovery 端：`scripts\toolchain\rollback\rollback_stock.sh`（LF 行尾，已验证 0 个 CR）
  - 定位 `/data/media/0/work/rollback`（自动尝试 mount /data，失败则明确报错且**不写分区**）→ sha256 预校验（不符即退出）→ 分区容量检查 → dd super → dd vendor_boot(当前槽) → sync → **整分区读回 sha256 对比** → PASS/FAIL → 默认 reboot
- 状态：脚本/清单完成，待 adb 空闲做一次真实 prepare（Lead 要求暂停设备操作）。

### 12.2 B：v0.2 super 构建器复核 + 实测 verify ✅
- 复核报告：`01_analysis\v02_super_build_review.md`
- 加固版构建器：`scripts\toolchain\build_super_v02_checked.ps1`（exact 1MiB 对齐布局模拟、`$LASTEXITCODE` 检查、输出大小检查、统一 group max、verify_super 自检、JSON manifest、`-DryRun` 秒级预算自检）
- 复核发现的 5 个问题（详见 review 文档）：`$pad=1MiB*9` 粗略估算；`limit(9,652,142,080)` 与 `--group(9,653,190,656)` 不一致 1 MiB；python 调用未查退出码（会静默校验 0 字节文件）；`scripts\lpdump.py` 的 **block_devices 64B 布局解析错误**（实测 stock super 打出 `name='r' size=7309471332004003842`，正确应为 `name=super size=9663676416`）；9 分区构建与 B 槽元数据缺失的适用范围说明。
- **v0.2 精确布局（system=5,894,299,648）**：Σ=9,382,387,712；data_end=9,387,200,512；对齐填充 3,764,224；data_end 后物理余量 276,475,904 (263.67 MiB)；Σ vs group max 余量 269,754,368 (257.26 MiB)。
- **Lead 已构建的 `G:\OriginOS_Work\04_build\v02_super.img` 离线验收结果：PASS**（详见 `01_analysis\v02_super_verify_report.md`）
  - 9,663,676,416 B，`sha256=9C9C41F65E62087F5841D9900D170D6A450D37516B7FF4CFDE8B70ADE11DFA23`
  - LP geometry/metadata/header/tables checksum 全部正确；9 分区顺序与大小、extent 起始/结束与复核预测**逐字节区间一致**（product 1,048,576→395,030,528 … odm_dlkm 9,386,852,352→9,387,200,512）
  - 每个分区首 extent 处 erofs magic 全部识别；无重叠、无越界；group main_a 已用 9,382,387,712 ≤ max 9,653,190,656
  - 抽回 8 个可对照分区与输入镜像 sha256 **全部 MATCH**；system_a 源镜像已不存在，改用 EROFS 自检：inodes=18,356（vivo 原 19,182，精简 826）、legacy LZ4 压缩已生效（lz4_max_distance=0xFFFF）
  - 已把从 v02 super 抽回的 trimmed vivo system 存为 `G:\OriginOS_Work\04_build\vivo_system_trimmed_5894299648.img`（5,894,299,648 B，sha256=`cb4878d4f35b054c30cddd3f39f2c6ae65c8545e4434b1bc6d490acde0a41cb7`），可作后续构建输入

### 12.3 C：VINTF HAL 差异分析（工具就绪，数据待 adb 空闲）⏳
- 分析器：`scripts\toolchain\analyze_vivo_boot_requirements.py`（内置 `--selftest`，已 PASS）
  - 解析 vivo system 的 `compatibility_matrix*.xml`（取 type=framework），与 rothko vendor/odm 的 `manifest*.xml`（type=device）比对：format/name/version major(+minor)/interface/instance
  - 分级：`BLOCKER_HIGH`（matrix 必选且属 system_server 启动强依赖集合）/ `BLOCKER_MED`（必选但非强依赖）/ `OPTIONAL`（matrix optional=true）
  - 输出 JSON + Markdown 表
- 数据收集脚本：`scripts\toolchain\pull_vintf.sh`（只读 tar vivo 解包树的 `system/etc/vintf` 与设备 `/vendor|/odm|/system_ext|/system/etc/vintf`，输出到 /data/local/tmp 供拉取；用 `device_run.ps1` 以文件方式运行，避免 `adb shell su -c` 内联引号坑）
- 阻断原因：按 Lead 要求 20-30 分钟内不碰 adb；等 "adb 空闲" 通知后 2 分钟即可完成。

### 12.4 本轮踩坑记录（供后续复用）
1. **PowerShell 5.1 读取无 BOM 的 UTF-8 .ps1 会按 ANSI(GBK) 解码** → 中文注释里的全角括号/引号会被误解析成语法错误。修复：项目内所有含中文的 .ps1 已加 UTF-8 BOM（`device_run.ps1`、`roundtrip.ps1`）。
2. **PowerShell 不允许把 `-f` 放在换行后的表达式续行**（`("..." \n -f ...)` 会报"缺少右)"），必须把 `-f` 与格式串放同一行。
3. **`adb shell su -c "cd X && tar ..."` 的内层双引号会被 PowerShell 剥掉** → 退化成 `su -c cd X && tar ...`，tar 在 `/` 下归档整个文件系统（本次已发生并被 kill）。正确做法：把命令写成设备端 `.sh` 文件用 `device_run.ps1` 推送执行，或使用单引号/脚本文件。
4. `scripts\bootimg.py unpack` 不支持 vendor_boot（会报 `unsupported header version`），vendor_boot 结构验证以 `patch_vendor_boot.py` 的 reparse + 区域逐字节比对为准。
5. recovery 状态下 `/sdcard` 可写（Lead 的 flash 流程可用），但 **root 在 Android 模式下不能直接写 /data/media/0**（FUSE/SELinux），staging 要用 `adb push`（shell 身份）到 `/sdcard/work/...`。


